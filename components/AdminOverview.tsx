'use client';
import {useI18n} from '@/components/I18n';
import {useDocumentNavigation} from './Navigation';
import {adminPath} from '@/lib/navigation';
import {Dashboard} from './Dashboard';
export function AdminOverview(){const {navigate}=useDocumentNavigation();return <Dashboard go={page=>{void navigate(adminPath(page));}}/>}
