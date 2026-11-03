import {publicMetadata} from '@/lib/site-metadata';
import {Earnings} from '@/components/marketing/Earnings';
export const generateMetadata=()=>publicMetadata('/landing/earnings','Salaries & earnings · Evzon','First-month salary of $500, performance reviews and the opportunity to earn more as you improve.');
export default function Page(){return <Earnings/>}
