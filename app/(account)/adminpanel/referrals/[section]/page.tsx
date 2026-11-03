import {notFound} from 'next/navigation';
import {referralTabs} from '@/lib/navigation';
import {ReferralsAdmin} from '@/components/ReferralsAdmin';
export default async function Page({params}:{params:Promise<{section:string}>}){const {section}=await params;if(!Object.hasOwn(referralTabs,section))notFound();return <ReferralsAdmin tab={referralTabs[section as keyof typeof referralTabs]}/>}
