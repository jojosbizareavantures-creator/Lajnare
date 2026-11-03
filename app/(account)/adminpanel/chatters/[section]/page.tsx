import {notFound} from 'next/navigation';
import {ChatterAdmin} from '@/components/chatter/ChatterAdmin';
import {chatterAdminSections} from '@/lib/chatter';
export default async function Page({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!(chatterAdminSections as readonly string[]).includes(section))notFound();return <ChatterAdmin section={section}/>;}
