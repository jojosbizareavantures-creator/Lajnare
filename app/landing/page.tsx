import {publicMetadata} from '@/lib/site-metadata';
import {getReferralOffer} from '@/lib/referral-offer-server';
export const dynamic='force-dynamic';
import {Home} from '@/components/marketing/Home';
export const generateMetadata=()=>publicMetadata('/landing','Evzon · Your next chapter starts here','Explore chatting roles on OnlyFans and Fanvue, practical training and career opportunities with Evzon.');
export default async function Page(){return <Home offer={await getReferralOffer()}/>}
