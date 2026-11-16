"""Read aggregate domain workload facts from ledger.sqlite; exclude credentials and dump bytes."""
import hashlib
import json
import re
import sqlite3
import sys
from collections import Counter,defaultdict
from datetime import datetime,timezone
from pathlib import Path

DATABASE=Path(r'D:\Services\dump-ledger-runtime\data\ledger.sqlite')
STAGE=Path(r'D:\ModelMirrors\staging\s8-dumpledger-workload-20261116')
TABLES=['customers','cases','dumps','upload_grants','audit_events','modules','symbol_artifacts',
        'dump_analyses','analysis_details','webhook_subscriptions','webhook_deliveries','schema_migrations']


def safe_word(value):
    return value if isinstance(value,str) and re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,63}',value) else 'unrecognized-'+hashlib.sha256(str(value).encode()).hexdigest()[:16]


def main():
    assert DATABASE.name=='ledger.sqlite' and DATABASE.is_file()
    directory=STAGE/'private'
    assert directory.is_dir(),'private host stage must be admitted first'
    connection=sqlite3.connect(DATABASE.as_uri()+'?mode=ro',uri=True,timeout=5,isolation_level=None)
    connection.execute('PRAGMA query_only=ON')
    assert connection.execute('PRAGMA query_only').fetchone()[0]==1
    connection.execute('BEGIN')
    tables={row[0] for row in connection.execute("SELECT name FROM sqlite_schema WHERE type='table'")}
    counts={name:connection.execute('SELECT count(*) FROM "'+name+'"').fetchone()[0] for name in TABLES if name in tables}
    columns={name:[row[1] for row in connection.execute('PRAGMA table_info("'+name+'")')] for name in TABLES if name in tables}
    actions=[]
    for action,count,first,last in connection.execute('SELECT action,count(*),min(occurred_at),max(occurred_at) FROM audit_events GROUP BY action ORDER BY action'):
        assert all(isinstance(value,str) and re.fullmatch(r'[0-9TZ:+.\-]{10,40}',value) for value in [first,last])
        actions.append({'action':safe_word(action),'count':count,'firstAt':first,'lastAt':last})
    bounds=connection.execute('SELECT min(rowid),max(rowid),count(*) FROM audit_events').fetchone()
    details=defaultdict(Counter)
    samples=connection.execute('SELECT action,detail_json FROM audit_events WHERE length(detail_json)<=16384 ORDER BY rowid DESC LIMIT 80').fetchall()
    for action,raw in samples:
        try:value=json.loads(raw)
        except (TypeError,ValueError):details[safe_word(action)]['invalid-json']+=1;continue
        if isinstance(value,dict):
            for key in value:details[safe_word(action)][safe_word(key)]+=1
    states=[]
    for phase,blob,validation,coverage,count in connection.execute('SELECT phase,blob_state,validation,coverage,count(*) FROM dumps GROUP BY phase,blob_state,validation,coverage'):
        states.append({'phase':safe_word(phase),'blobState':safe_word(blob),'validation':safe_word(validation),
                       'coverage':None if coverage is None else safe_word(coverage),'count':count})
    schema_version=connection.execute('SELECT max(version) FROM schema_migrations').fetchone()[0] if 'schema_migrations' in tables else None
    assert connection.total_changes==0
    connection.execute('ROLLBACK');connection.close()
    result={'schema':'mirrors.s8.dumpledger-domain-inventory/v1','observedAtUtc':datetime.now(timezone.utc).isoformat(),
            'databasePath':str(DATABASE),'databaseBytes':DATABASE.stat().st_size,
            'pythonVersion':sys.version,'sqliteVersion':sqlite3.sqlite_version,'databaseOpenedReadOnly':True,
            'queryOnly':True,'singleReadTransaction':True,'schemaVersion':schema_version,'tableCounts':counts,
            'domainColumnNames':columns,'actionCounts':actions,'dumpStateCounts':states,
            'auditReadBounds':{'minRowid':bounds[0],'maxRowid':bounds[1],'rows':bounds[2]},
            'sampledDetailFieldNames':{name:dict(values) for name,values in details.items()},
            'sampledDetailRecords':len(samples),'detailValuesReturned':False,'customerOrDumpNamesReturned':False,
            'authDatabaseOrEnvRead':False,'grantOrWebhookSecretsSelected':False,'dumpBytesRead':False,
            'databaseChangesByCollector':0,'serviceRestarted':False,'formalConformanceClaimed':False}
    raw=json.dumps(result,indent=2)+'\n'
    with (directory/'domain-inventory.json').open('x',encoding='utf-8') as stream:stream.write(raw)
    print(raw)


if __name__=='__main__':main()
