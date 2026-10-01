import {pathToFileURL} from "node:url";
import {resolve} from "node:path";
const {connectTlsMirror,runClientValidate,specFromFiles}=await import(pathToFileURL(resolve(process.env.ECMA_REPO,"dist/index.js")));
const env=process.env;
const transport=await connectTlsMirror("172.20.208.1",8999,{caPath:env.MIRRORS_REMOTE_CA,certPath:env.MIRRORS_REMOTE_CLIENT_CERT,keyPath:env.MIRRORS_REMOTE_CLIENT_KEY,pin:env.MIRRORS_REMOTE_SERVER_PIN});
const spec=await specFromFiles(env.M5_INTEROP_SPEC);
const result=await runClientValidate(transport,{specPath:"HourClock.tla",invariant:env.M5_INTEROP_INV,lengthBound:Number(env.M5_INTEROP_BOUND),initPredicate:"Init",nextPredicate:"Next"},Number(env.M5_INTEROP_BOUND),{spec});
if(result==="valid"){console.log("VALID")}else{console.log("INVALID",JSON.stringify(result));process.exitCode=1}
