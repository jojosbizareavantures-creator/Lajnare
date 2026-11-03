export type TrainingAsset={name:string;title:string;caption:string};
export type TrainingUnit={id:string;day:number;section:string;title:string;title_mk:string;summary:string;body:string;body_mk:string;note:string;assets:TrainingAsset[];position:number;minutes:number;published:boolean;revision:number;source:string;unlocked:boolean};
export type StudyRead={chatter_id:string;unit_id:string;revision:number;read_at:string;notes:string};
export type LearningData={units:TrainingUnit[];reads:StudyRead[]};
export function isStudied(unit:TrainingUnit,reads:StudyRead[],chatterId:string){return reads.some(r=>r.chatter_id===chatterId&&r.unit_id===unit.id&&r.revision===unit.revision);}
