'use client';
import {useI18n,LanguageSelect} from '@/components/I18n';
import {PageLink as Link} from '@/components/marketing/PublicUI';
export default function NotFound(){const {t:tr}=useI18n();return <main className="not-found"><span className="marketing-kicker">{tr("404 · PAGE NOT FOUND")}</span><h1>{tr("Let’s get you back on track.")}</h1><p>{tr("This page does not exist. Choose a destination below.")}</p><div className="actions"><Link className="btn primary" href="/landing">{tr("Visit Evzon")}</Link><Link className="btn" href="/adminpanel">{tr("Admin workspace")}</Link><Link className="btn" href="/referrer">{tr("Partner portal")}</Link></div></main>}
