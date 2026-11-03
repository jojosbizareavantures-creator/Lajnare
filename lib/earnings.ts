import {FIRST_MONTH_PAY_USD} from './careers';
export type EarningsAssumptions={salary:number;bonus:number;hours:number;days:number};
export const earningsDefaults:EarningsAssumptions={salary:FIRST_MONTH_PAY_USD,bonus:0,hours:8,days:26};
export function estimateEarnings(v:EarningsAssumptions){
 if(Object.values(v).some(x=>!Number.isFinite(x)||x<0))throw new Error('Use non-negative finite assumptions.');
 const monthly=v.salary+v.bonus,scheduledHours=v.hours*v.days;
 return {firstYear:FIRST_MONTH_PAY_USD+monthly*11,monthly,annual:monthly*12,weekly:monthly*12/52,scheduledHours,effectiveHourly:scheduledHours?monthly/scheduledHours:0};
}
