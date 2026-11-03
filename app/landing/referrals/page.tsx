import {publicMetadata} from '@/lib/site-metadata';
import {getReferralOffer} from '@/lib/referral-offer-server';
export const dynamic='force-dynamic';
import {Referrals} from '@/components/marketing/Referrals';
export const generateMetadata=()=>publicMetadata('/landing/referrals','Refer & earn · Evzon','Introduce suitable candidates and track reviewed rewards in your partner portal.');
export default async function Page(){return <Referrals initialOffer={await getReferralOffer()}/>}
