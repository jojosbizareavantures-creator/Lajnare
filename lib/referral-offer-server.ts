import {anonymousClient} from './supabase-server';
import {validOffer,type ReferralOffer} from './referral-program';
export async function getReferralOffer():Promise<ReferralOffer|null>{
 try{const {data,error}=await anonymousClient().from('evzon_referral_config').select('training_bonus,training_days,first_month_bonus').single();return !error&&validOffer(data)?data:null;}catch{return null;}
}
