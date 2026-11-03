import {publicMetadata} from '@/lib/site-metadata';
import {Training} from '@/components/marketing/Training';
export const generateMetadata=()=>publicMetadata('/landing/training','Training & development · Evzon','Explore practical training, assessment, first-month pay and performance-based growth at Evzon.');
export default function Page(){return <Training/>}
