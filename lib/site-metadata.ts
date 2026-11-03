import {headers} from 'next/headers';
import type {Metadata} from 'next';
import {canonicalOrigin} from './site-config';

export async function publicMetadata(path: string, title: string, description: string): Promise<Metadata> {
  const origin = canonicalOrigin((await headers()).get('host'));
  const url = new URL(path, origin).href;
  return {
    title, description, metadataBase: new URL(origin),
    alternates: {canonical: url},
    openGraph: {type: 'website', siteName: 'Evzon', title, description, url},
    twitter: {card: 'summary', title, description},
  };
}
