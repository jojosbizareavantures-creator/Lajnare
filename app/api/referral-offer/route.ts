import {getReferralOffer} from '@/lib/referral-offer-server';
export const dynamic='force-dynamic';
export async function GET(){const offer=await getReferralOffer();return Response.json(offer?{offer}:{error:'Referral terms are temporarily unavailable. Please try again.'},{status:offer?200:503,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}});}
