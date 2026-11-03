import {notFound} from 'next/navigation';
import {referrerSections} from '@/lib/navigation';
export default async function Page({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!referrerSections.includes(section as typeof referrerSections[number]))notFound();return null;}
