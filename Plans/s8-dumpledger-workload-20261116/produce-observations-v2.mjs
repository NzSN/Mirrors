import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdirSync,statSync,readdirSync,realpathSync} from 'node:fs';
import {createRequire} from 'node:module';
import {join,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';

const app=String.raw`D:\Services\dump-ledger`;
const stage=String.raw`D:\ModelMirrors\staging\s8-dumpledger-workload-20261116`;
const privateRoot=join(stage,'private');
const hash=(raw)=>createHash('sha256').update(raw).digest('hex');
const fileIdentity=(path)=>({path,bytes:statSync(path).size,sha256:hash(readFileSync(path))});
const harnessPath=join(app,'dist/src/mbt/harness.js');
const bindingPath=join(app,'dist/src/generated/dump-ledger/DumpLedgerMirror.generated.js');
const requireApp=createRequire(pathToFileURL(join(app,'package.json')));
const sdkEntry=requireApp.resolve('mirrorecma/dist/index.js');
const codeFiles=(root)=>readdirSync(root,{withFileTypes:true}).flatMap(item=>{
  const path=join(root,item.name);assert(!item.isSymbolicLink());
  return item.isDirectory()?codeFiles(path):item.isFile()&&item.name.endsWith('.js')?[path]:[];
});
const implementationFiles=codeFiles(join(app,'dist/src')).sort().map(fileIdentity);
const before=[harnessPath,bindingPath,join(app,'dist/src/engine/dump-ledger-engine.js'),
  join(app,'dist/src/ledger/sqlite-ledger.js'),join(app,'dist/src/ledger/migrations.js'),
  join(app,'specs/DumpLedger.tla'),sdkEntry,join(dirname(sdkEntry),'protocol.js')].map(fileIdentity);
const {MbtHarness,DumpLedgerMbtPort,createMbtProbe}=await import(pathToFileURL(harnessPath));
const {bindDumpLedger,DumpLedgerSemanticDigest}=await import(pathToFileURL(bindingPath));
const sdk=await import(pathToFileURL(sdkEntry));
const codec=await import(pathToFileURL(join(dirname(sdkEntry),'protocol.js')));
assert.equal(typeof codec.encodeState,'function');
const encodeReportState=(state)=>JSON.stringify({proto_step:'report_state',state:codec.encodeState(state)});
const selection=JSON.parse(readFileSync(join(privateRoot,'workload-candidates.json'),'utf8'));
assert.equal(selection.candidates.length,3);
const admittedBytes={c95341bf4cb42031:1886624,'1a619a5600db6051':2589072,c57ec0cde7b7e01a:1414128};
assert.deepEqual(selection.candidates.map(item=>item.alias).sort(),Object.keys(admittedBytes).sort());
for(const item of selection.candidates)assert.equal(item.bytes,admittedBytes[item.alias]);
const output=join(privateRoot,'observations-v2');mkdirSync(output,{recursive:false});
const results=[];
const int=(value)=>({tag:'int',val:BigInt(value)});
const str=(value)=>({tag:'str',val:value});
for(const candidate of selection.candidates){
  const resolved=realpathSync(candidate.payloadPath).toLowerCase();
  assert(resolved.startsWith(String.raw`d:\services\dump-ledger-runtime\data\vault`+'\\'));
  assert(resolved.endsWith(String.raw`\original.dmp`));
  const payload=readFileSync(candidate.payloadPath);
  assert.equal(payload.length,candidate.bytes);assert.equal(hash(payload),candidate.sha256);
  assert.equal(candidate.grantMaxUploads,1);assert.equal(candidate.coverage,'partial');
  assert(BigInt(candidate.grantMaxBytes)>=BigInt(payload.length));
  assert.deepEqual(candidate.sourceCommands.map(row=>row.action),
    ['IssueGrant','BeginUpload','SealUpload','PromoteObject','MarkQuarantined','AcceptDump']);
  const probe=createMbtProbe();
  const harness=new MbtHarness(probe,{uploadBytes:payload,productionInspection:true});
  // The existing finite harness fixes maxBytes to 1024, an unmodeled setting.
  // Restore the selected real grant's budget at the adapter command seam;
  // production engine code and generated dispatch/observation stay untouched.
  const execute=harness.execute.bind(harness);
  harness.execute=(command)=>execute(command.type==='IssueGrant'
    ?{...command,maxBytes:BigInt(candidate.grantMaxBytes)}:command);
  const port=new DumpLedgerMbtPort(harness,probe);
  const binding=bindDumpLedger(port,{specPath:join(app,'specs/DumpLedger.tla'),
    invariant:'SafetyInvariant',lengthBound:6,paramVars:'parameters'});
  const frames=[];
  const record=(action,values={})=>{
    const native={case:int(0),dump:int(0),kind:str('unclassified'),token:int(0),...values};
    const parameters={parameters:{tag:'record',val:native}};
    // No expected model state is read or supplied to the computer.
    const observed=binding.computer(action,parameters,Object.freeze({}));
    frames.push({action,report:encodeReportState(observed)});
  };
  try{
    record('Init');
    for(const command of candidate.sourceCommands){
      switch(command.action){
      case 'IssueGrant':record('IssueToken',{token:int(1)});break;
      case 'BeginUpload':record('BeginUpload',{token:int(1),dump:int(1)});break;
      case 'SealUpload':record('SealUpload',{dump:int(1)});break;
      case 'PromoteObject':record('PromoteObject',{dump:int(1)});break;
      case 'MarkQuarantined':record('MarkQuarantined',{dump:int(1)});break;
      case 'AcceptDump':record('AcceptDump',{dump:int(1),kind:str(candidate.coverage)});break;
      default:throw new Error('unadmitted source action');
      }
    }
    assert.equal(frames.length,7);
    assert.equal(JSON.parse(frames.at(-1).report).state.coverage[0],'partial');
    assert.equal(probe.sessionCreates,1);assert.equal(probe.engineCalls,10);
  }finally{harness.dispose();}
  assert.equal(probe.sessionCloses,1);
  assert.equal(hash(readFileSync(candidate.payloadPath)),candidate.sha256);
  const name=candidate.alias+'.json';
  const value={schema:'mirrors.s8.production-input-observations/v1',alias:candidate.alias,
    inputBytes:candidate.bytes,inputSha256:candidate.sha256,
    sourceCommandRows:candidate.sourceCommands,normalizedFiniteSlots:{case:1,grant:1,dump:1},
    timestampNormalization:'deterministic harness clock; timestamps are outside this model observation',
    grantMaxBytesFromSource:true,productionInspectionUsed:true,sqliteMode:'fresh :memory: instance',
    expectedTraceReadByProducer:false,previousExpectedStateSupplied:false,
    productionDatabaseOpenedByReplay:false,payloadBytesIncluded:false,
    scope:'six-command one-shot partial-dump lifecycle slice; HTTP/auth/streaming and later audit actions excluded',
    sourceOtherActionCounts:candidate.sourceDumpOtherActionCounts,frames,
    sessionsCreated:probe.sessionCreates,sessionsClosed:probe.sessionCloses,engineCalls:probe.engineCalls};
  const raw=Buffer.from(JSON.stringify(value,null,2)+'\n');
  writeFileSync(join(output,name),raw,{flag:'wx'});
  results.push({alias:candidate.alias,inputBytes:candidate.bytes,frames:frames.length,
    sourceCommands:candidate.sourceCommands.length,sessionsCreated:1,sessionsClosed:1,
    artifact:{name,bytes:raw.length,sha256:hash(raw)}});
}
for(const original of before)assert.equal(fileIdentity(original.path).sha256,original.sha256);
for(const original of implementationFiles)assert.equal(fileIdentity(original.path).sha256,original.sha256);
const nativeAddons=Object.keys(requireApp.cache).filter(path=>path.endsWith('.node')).map(fileIdentity);
const receipt={schema:'mirrors.s8.dumpledger-observation-producer/v1',
  status:'three-production-retained-inputs-replayed-in-isolated-engine',at:new Date().toISOString(),
  nodeVersion:process.version,nodeExecutable:fileIdentity(process.execPath),
  modelSemanticDigest:DumpLedgerSemanticDigest,implementationInputs:before,
  reportEncoder:'deployed SDK protocol.encodeState plus report_state envelope',
  implementationFileCount:implementationFiles.length,
  implementationTreeIndexSha256:hash(JSON.stringify(implementationFiles)),nativeAddons,
  selectedCandidates:results,totalObservationFrames:results.reduce((n,item)=>n+item.frames,0),
  rawDumpBytesExported:false,expectedTraceReadByProducer:false,productionDatabaseOpenedByReplay:false,
  productionServiceOrDataMutated:false,realVersusTestOriginIndependentlyCertified:false,
  historicalWireOrFullSoakAcceptanceClaimed:false};
writeFileSync(join(output,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(receipt,null,2));
