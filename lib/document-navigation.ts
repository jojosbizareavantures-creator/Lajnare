export type LeaveGuard = () => void | Promise<void>;
type NavigationState = {pending:boolean;error:string};

// A document request works independently of the framework's RSC/prefetch cache.
// One coordinator also prevents double clicks from starting competing saves.
export function createDocumentNavigation(
  visit:(href:string,replace:boolean)=>void,
  status:(state:NavigationState)=>void=()=>{},
){
  let guard:LeaveGuard|undefined;
  let pending:Promise<boolean>|null=null;
  return {
    register(next:LeaveGuard){guard=next;return ()=>{if(guard===next)guard=undefined;};},
    hasGuard:()=>!!guard,
    prepare:async()=>{await guard?.();},
    navigate(href:string,replace=false):Promise<boolean>{
      if(pending)return pending;
      // All programmatic destinations are internal, including after sign-in.
      if(!href.startsWith('/')||href.startsWith('//')||/[\\\r\n]/.test(href)){
        status({pending:false,error:'This page could not be opened. Please use the navigation menu.'});
        return Promise.resolve(false);
      }
      status({pending:true,error:''});
      pending=Promise.resolve().then(()=>guard?.()).then(()=>{
        visit(href,replace);status({pending:false,error:''});return true;
      }).catch((error:unknown)=>{
        status({pending:false,error:error instanceof Error?error.message:'Your changes could not be saved. Please retry before leaving.'});
        return false;
      }).finally(()=>{pending=null;});
      return pending;
    },
  };
}

export function isPlainInternalClick(event:{defaultPrevented:boolean;button:number;metaKey:boolean;ctrlKey:boolean;shiftKey:boolean;altKey:boolean},href?:string,target?:string,download?:unknown){
  return !event.defaultPrevented&&event.button===0&&!event.metaKey&&!event.ctrlKey&&!event.shiftKey&&!event.altKey&&(!target||target==='_self')&&download===undefined&&!!href&&href.startsWith('/')&&!href.startsWith('//');
}

// Drain edits made during an in-flight autosave before leaving the document.
// A failed save rejects: navigation must keep the user and their draft in place.
export async function saveBeforeLeaving(hasChanges:()=>boolean,save:()=>Promise<void>){
  while(hasChanges())await save();
}
