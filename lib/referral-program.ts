export type ReferralOffer={training_bonus:number;training_days:number;first_month_bonus:number};
export function validOffer(value:unknown):value is ReferralOffer{
 if(!value||typeof value!=='object')return false;
 const v=value as ReferralOffer;
 return [v.training_bonus,v.first_month_bonus].every(n=>typeof n==='number'&&Number.isFinite(n)&&n>=0&&n<=100000)&&Number.isInteger(v.training_days)&&v.training_days>=1&&v.training_days<=365;
}
export function referralEstimate(offer:ReferralOffer,trained:number,firstMonth:number){
 if(!validOffer(offer)||!Number.isInteger(trained)||!Number.isInteger(firstMonth)||trained<0||trained>10000||firstMonth<0||firstMonth>trained)throw new Error('Enter whole candidate counts from 0 to 10,000; month completions cannot exceed training completions.');
 const training=Math.round(offer.training_bonus*trained*100)/100,month=Math.round(offer.first_month_bonus*firstMonth*100)/100;
 return {training,month,total:Math.round((training+month)*100)/100};
}
export function firstMonthDue(hiredOn:string){
 const match=/^(\d{4})-(\d{2})-(\d{2})$/.exec(hiredOn);if(!match)return '';
 const year=Number(match[1]),month=Number(match[2]),day=Number(match[3]);
 const date=new Date(Date.UTC(year,month-1,day));if(date.toISOString().slice(0,10)!==hiredOn)return '';
 const last=new Date(Date.UTC(year,month+1,0)).getUTCDate();
 return new Date(Date.UTC(year,month,Math.min(day,last))).toISOString().slice(0,10);
}
