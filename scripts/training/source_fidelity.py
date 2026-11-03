"""Verify source wording, recorded user removals, and formatting-only edits."""
from pathlib import Path
import hashlib
import json
import re
import base64

FOLDER = Path(__file__).resolve().parents[2] / 'content/training'

def corrections():
    path = FOLDER / 'user-corrections.json'
    return json.loads(path.read_text())['edits'] if path.exists() else []

def formatting_edits():
    path = FOLDER / 'formatting-edits.json'
    return json.loads(path.read_text())['edits'] if path.exists() else []

def clarifications():
    path = FOLDER / 'user-clarifications.json'
    return json.loads(path.read_text())['edits'] if path.exists() else []

def image_additions():
    path = FOLDER / 'image-additions.json'
    return json.loads(path.read_text())['images'] if path.exists() else []

def apply_clarifications(text, unit_id, field='body'):
    for edit in clarifications():
        if edit['unit_id'] == unit_id and edit['field'] == field:
            assert text.count(edit['before']) == 1, f"Clarification source changed: {unit_id} {field}"
            text = text.replace(edit['before'], edit['after'], 1)
    return text

def restore_clarifications(text, unit_id, field='body'):
    for edit in reversed(clarifications()):
        if edit['unit_id'] == unit_id and edit['field'] == field:
            assert text.count(edit['after']) == 1, f"Clarification missing or changed: {unit_id} {field}"
            text = text.replace(edit['after'], edit['before'], 1)
    return text

def verify_formatting(edit):
    before, after = edit['before'], edit['after']
    assert re.findall(r'\w+', before) == re.findall(r'\w+', after), f"Wording changed: {edit['unit_id']} {edit['field']}"
    # Only Markdown layout, whitespace and full stops may differ. Case, word
    # order, original examples, numbers and other punctuation stay untouched.
    normalize = lambda text: re.sub(r'[\s.#*>-]', '', text)
    assert normalize(before) == normalize(after), f"Non-formatting change: {edit['unit_id']} {edit['field']}"

def apply_formatting(text, unit_id, field='body'):
    for edit in formatting_edits():
        if edit['unit_id'] != unit_id or edit['field'] != field:
            continue
        verify_formatting(edit)
        assert text in (edit['before'], edit['after']), f"Formatting source changed: {unit_id} {field}"
        text = edit['after']
    return apply_clarifications(text, unit_id, field)

def restore_formatting(unit, field='body'):
    text = restore_clarifications(unit[field], unit['id'], field)
    for edit in reversed(formatting_edits()):
        if edit['unit_id'] != unit['id'] or edit['field'] != field:
            continue
        verify_formatting(edit)
        assert text == edit['after'], f"Formatting missing or changed: {unit['id']} {field}"
        text = edit['before']
    return text

def restore_original(unit, field='body'):
    text = restore_formatting(unit, field)
    for edit in reversed(corrections()):
        if edit['unit_id'] != unit['id'] or edit['field'] != field:
            continue
        assert text.count(edit['after']) == 1, f"Correction missing or changed: {unit['id']} {field}"
        assert edit['before'] not in text, f"Rejected passage restored: {unit['id']} {field}"
        text = text.replace(edit['after'], edit['before'], 1)
    return text

def verify_course():
    course = json.loads((FOLDER / 'curriculum.json').read_text())
    manifest = json.loads((FOLDER / 'course-manifest.json').read_text())
    by_id = {u['id']: u for u in course}
    original = ''.join(restore_original(by_id[id]) for id in manifest['base_ids'])
    assert hashlib.sha256(original.encode()).hexdigest() == manifest['base_sha256'], 'Unapproved changes to source text'
    supplement = ''.join(restore_formatting(by_id[id]) for id in manifest['supplement_ids'])
    assert supplement == (FOLDER / manifest['supplement_source']).read_text(), 'Supplement differs from supplied text'
    for unit in course:
        assert unit['body_mk'] == (FOLDER / 'mk' / f"{unit['id']}.md").read_text(), 'Translation file mismatch'
        restore_original(unit, 'body_mk')
        assert not unit['summary'] and not unit['note'], 'Added chapter guidance'
    additions = image_additions()
    originals = json.loads((FOLDER / 'source-manifest.json').read_text())['images']
    expected = originals + additions
    actual = [(u['id'], a) for u in course for a in u['assets']]
    assert len(actual) == manifest['original_images'] + manifest.get('additional_images', 0)
    assert len(additions) == manifest.get('additional_images', 0)
    assert len({a['name'] for _, a in actual}) == len(actual), 'Duplicate image placement'
    assert {a['name'] for _, a in actual} == {a['name'] for a in expected}, 'Missing or unexpected image'
    stored = json.loads((FOLDER.parents[1] / 'lib/server/training-assets.json').read_text())
    for image in expected:
        unit = by_id[image['unit']]
        assert unit['day'] == image['day'], 'Image attached to the wrong material'
        assert {k: image[k] for k in ('name', 'title', 'caption')} in unit['assets'], 'Image placement or label changed'
        assert image['name'] in stored, 'Image data missing'
        if 'sha256' in image:
            assert hashlib.sha256(base64.b64decode(stored[image['name']], validate=True)).hexdigest() == image['sha256'], 'Uploaded image changed'
    assert all(edit['unit_id'] in by_id and edit['field'] in ('body', 'body_mk') for edit in formatting_edits())
    assert all(edit['unit_id'] in by_id and edit['field'] in ('body', 'body_mk') for edit in clarifications())
    print(f"Verified {len(course)} chapters: source wording and order preserved except recorded user corrections and clarifications; translations synchronized; images preserved.")

if __name__ == '__main__':
    verify_course()
