import {publicMetadata} from '@/lib/site-metadata';
import {FAQ} from '@/components/marketing/FAQ';
export const generateMetadata=()=>publicMetadata('/landing/faq','Questions & answers · Evzon','Answers about the role, training, earnings, applications and referrals.');
export default function Page(){return <FAQ/>}
