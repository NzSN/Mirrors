"""Select bounded production-retained lifecycle inputs without exposing names or payloads."""
import hashlib
import json
import re
import sqlite3
from collections import Counter
from datetime import datetime,timezone
from pathlib import Path

DATA=Path(r'D:\Services\dump-ledger-runtime\data')
PRIVATE=Path(r'D:\ModelMirrors\staging\s8-dumpledger-workload-20261116\private')
STEPS=['BeginUpload','SealUpload','PromoteObject','MarkQuarantined','AcceptDump']


def alias(value):return hashlib.sha256(value.encode()).hexdigest()[:16]


def main():
    connection=sqlite3.connect((DATA/'ledger.sqlite').as_uri()+'?mode=ro',uri=True,isolation_level=None,timeout=5)
    connection.execute('PRAGMA query_only=ON');connection.execute('BEGIN')
    caps=[{'maxUploads':cap,'state':state,'count':count} for cap,state,count in connection.execute('SELECT max_uploads,state,count(*) FROM upload_grants GROUP BY max_uploads,state ORDER BY max_uploads,state')]
    rows=connection.execute('SELECT d.dump_id,d.case_id,d.byte_size,d.sha256,d.coverage,d.original_name,c.title,c.status FROM dumps d JOIN cases c ON c.case_id=d.case_id WHERE d.phase=\'available\' AND d.coverage=\'partial\' ORDER BY d.received_at,d.dump_id').fetchall()
    rejected=Counter();candidates=[]
    for dump_id,case_id,byte_size,digest,coverage,name,title,status in rows:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}',dump_id):rejected['unsafe-identifier']+=1;continue
        size=int(byte_size)
        if not 4096<=size<=8*1024*1024:rejected['outside-declared-byte-bound']+=1;continue
        if re.search(r'(?:test|fixture|smoke|synthetic|mbt|seed)',name+' '+title,re.IGNORECASE):rejected['test-marker-in-private-name-or-title']+=1;continue
        events=connection.execute('SELECT rowid,occurred_at,action FROM audit_events WHERE dump_id=? ORDER BY rowid',(dump_id,)).fetchall()
        lifecycle=[(index,at,action) for index,at,action in events if action in STEPS]
        if [row[2] for row in lifecycle]!=STEPS:rejected['lifecycle-not-exact-declared-prefix']+=1;continue
        grant_row=connection.execute("SELECT json_extract(detail_json,'$.grantId') FROM audit_events WHERE dump_id=? AND action='BeginUpload' ORDER BY rowid",(dump_id,)).fetchall()
        if len(grant_row)!=1:rejected['ambiguous-grant-association']+=1;continue
        grant_id=grant_row[0][0]
        grant=connection.execute('SELECT max_uploads,uploads_used,max_bytes,state FROM upload_grants WHERE grant_id=?',(grant_id,)).fetchone()
        if grant is None or grant[0]!=1 or grant[1]!=1 or grant[3]!='consumed':rejected['outside-one-shot-grant-profile']+=1;continue
        issued=connection.execute("SELECT rowid,occurred_at FROM audit_events WHERE action='IssueGrant' AND json_extract(detail_json,'$.grantId')=? ORDER BY rowid",(grant_id,)).fetchall()
        if len(issued)!=1 or issued[0][0]>=lifecycle[0][0]:rejected['missing-or-misordered-grant-issue']+=1;continue
        workflow=connection.execute("SELECT count(*) FROM audit_events WHERE case_id=? AND action IN ('StartInvestigation','WaitForCustomer','ResumeInvestigation','ResolveCase','CloseCase') AND rowid<=?",(case_id,lifecycle[-1][0])).fetchone()[0]
        if workflow:rejected['case-workflow-outside-initial-new-profile']+=1;continue
        path=DATA/'vault'/dump_id/'original.dmp'
        if not path.is_file() or not path.resolve().is_relative_to((DATA/'vault').resolve()):rejected['missing-or-aliased-vault-input']+=1;continue
        if path.stat().st_size!=size:rejected['vault-byte-size-mismatch']+=1;continue
        actual=hashlib.sha256(path.read_bytes()).hexdigest()
        if actual!=digest:rejected['vault-digest-mismatch']+=1;continue
        candidates.append({'alias':alias(dump_id),'dumpId':dump_id,'caseId':case_id,'grantId':grant_id,
                           'payloadPath':str(path),'bytes':size,'sha256':digest,'coverage':coverage,
                           'grantMaxBytes':grant[2],'grantMaxUploads':1,'sourceCurrentCaseStatus':status,
                           'sourceCommands':[{'rowid':issued[0][0],'at':issued[0][1],'action':'IssueGrant'}]+[
                               {'rowid':index,'at':at,'action':action} for index,at,action in lifecycle],
                           'sourceDumpOtherActionCounts':dict(Counter(row[2] for row in events if row[2] not in STEPS)),
                           'nameAndTitleValuesRetained':False,'realVersusTestOriginIndependentlyProved':False})
    bounds=connection.execute('SELECT max(rowid),count(*) FROM audit_events').fetchone()
    assert connection.total_changes==0;connection.execute('ROLLBACK');connection.close()
    # Keep a bounded candidate set. Real payload bytes stay in their existing vault.
    selected=candidates[:3]
    private={'schema':'mirrors.s8.private-dumpledger-candidates/v1','at':datetime.now(timezone.utc).isoformat(),
             'sourceAuditMaxRowid':bounds[0],'sourceAuditRows':bounds[1],'candidates':selected,
             'scope':'production-retained one-shot partial-dump lifecycle slice; no historical wire/conformance claim'}
    with (PRIVATE/'workload-candidates.json').open('x',encoding='utf-8') as stream:stream.write(json.dumps(private,indent=2)+'\n')
    summary={'schema':'mirrors.s8.dumpledger-candidate-summary/v1','at':private['at'],'availablePartialDumpRows':len(rows),
             'grantCapacityCounts':caps,'eligibleCandidates':len(candidates),'selectedCandidates':[
                 {key:item[key] for key in ['alias','bytes','coverage','grantMaxUploads']} for item in selected],
             'selectionExclusions':dict(rejected),'selectedPayloadHashesMatchLedger':True,
             'payloadBytesExported':False,'productionDomainRowsChanged':0,'authDatabaseOrSecretsRead':False,
             'customerOrDumpNamesReturned':False,'historicalWireConformanceClaimed':False}
    with (PRIVATE/'candidate-summary.json').open('x',encoding='utf-8') as stream:stream.write(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
