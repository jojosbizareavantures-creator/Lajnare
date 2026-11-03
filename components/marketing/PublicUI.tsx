'use client';
import {useI18n} from '@/components/I18n';
import type {ComponentPropsWithoutRef} from 'react';
// Public links are ordinary document navigation, including before hydration.
// WorkspaceLink adds save-before-leave protection for authenticated dashboards.
export function PageLink(props:ComponentPropsWithoutRef<'a'>){return <a {...props}/>}
export function SectionNav({items}:{items:{href:string;label:string}[]}){const {t:tr}=useI18n();return <nav className="marketing-container guide-nav" aria-label={tr("On this page")}>{items.map(item=><PageLink key={item.href} href={item.href}>{tr(item.label)}</PageLink>)}</nav>}
