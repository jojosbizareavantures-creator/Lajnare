import {notFound} from 'next/navigation';
import {ChatterPortal} from '@/components/chatter/ChatterPortal';
import {chatterSections} from '@/lib/chatter';
export default async function Page({params}:{params:Promise<{section?:string[]}>}){const {section=[]}=await params;if(section.length>1||section[0]&&!(chatterSections as readonly string[]).includes(section[0]))notFound();return <ChatterPortal section={section[0]||'dashboard'}/>;}

