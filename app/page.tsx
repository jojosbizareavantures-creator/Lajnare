import {redirect} from 'next/navigation';
import {legacyEntry} from '@/lib/navigation';
export default async function Page({searchParams}:{searchParams:Promise<Record<string,string|string[]|undefined>>}){redirect(legacyEntry(await searchParams));}
