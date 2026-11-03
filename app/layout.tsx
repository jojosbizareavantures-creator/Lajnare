import {cookies} from 'next/headers';
import {I18nProvider} from '@/components/I18n';
import {GoogleAnalytics} from '@/components/GoogleAnalytics';
import {languageFrom,LANGUAGE_COOKIE} from '@/lib/i18n';
import './globals.css';
import './marketing.css';
import './i18n.css';
import './applications.css';
import './updates.css';
import './referrals.css';
import './chatter.css';
import './exams.css';
import './analytics.css';
export const metadata={title:'Evzon · People & potential',description:'Chatting roles on OnlyFans and Fanvue, practical training and career development. Based in North Macedonia.',icons:{icon:'/favicon.svg'}};
export default async function Layout({children}:{children:React.ReactNode}){const language=languageFrom((await cookies()).get(LANGUAGE_COOKIE)?.value);return <html lang={language||'en'}><head><link rel="preconnect" href="https://fonts.googleapis.com"/><link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin=""/>
 {/* eslint-disable-next-line @next/next/no-page-custom-font -- The root layout loads these fonts once for every page. */}
 <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geologica:wght,SHRP@100..900,0..100&family=IBM+Plex+Mono:wght@400;500;600&display=swap"/></head><body><I18nProvider initialLanguage={language}>{children}<GoogleAnalytics/></I18nProvider></body></html>}
