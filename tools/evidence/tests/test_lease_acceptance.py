import copy
import hashlib
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import collect

CLEANUP={'scope':'local','status':'succeeded','quiescence':'confirmed','bindingStatus':'succeeded'}
def suite(outcome):
    s={'schema':'mirrorecma.suite-result/v1','suiteId':'lease-service.reference-installed/v1','outcome':outcome,'conformance':'matched' if outcome=='passed' else 'mismatch','cleanup':CLEANUP.copy(),'acceptance':{'status':'met' if outcome=='passed' else 'incomplete'}}
    if outcome=='mismatch':s['failure']={'kind':'mismatch','code':'model_mismatch','traceIndex':0,'stateIndex':5,'action':'write'}
    return s
class LeaseAcceptanceTests(unittest.TestCase):
    def test_origin_requires_exact_fault_and_clean_baseline(self):
        plan=type('Plan',(),{'application':'lease-faulty','adapter_artifact_id':'lease-origin'})();obs=collect.ChildObservation(1,False,False,b'',b'',False,False)
        raw={'lease-origin':json.dumps(suite('mismatch')).encode(),'lease-baseline':json.dumps(suite('passed')).encode()}
        self.assertEqual(collect._suite_result_outcomes(plan,raw,obs)[2],'passed')
        for case in ['missing-baseline','bad-cleanup','wrong-coordinate','wrong-suite','bad-baseline','wrong-action']:
            c=copy.deepcopy(raw)
            if case=='missing-baseline':c.pop('lease-baseline')
            elif case in ['bad-baseline','bad-cleanup']:
                b=json.loads(c['lease-baseline']);b['acceptance']=None if case=='bad-baseline' else b['acceptance'];b['cleanup']['status']='failed' if case=='bad-cleanup' else 'succeeded';c['lease-baseline']=json.dumps(b).encode()
            else:
                f=json.loads(c['lease-origin'])
                if case=='wrong-coordinate':f['failure']['stateIndex']=1
                if case=='wrong-suite':f['suiteId']='work-queue.reference-installed/v1'
                if case=='wrong-action':f['failure']['action']='enqueue'
                c['lease-origin']=json.dumps(f).encode()
            with self.subTest(case=case),self.assertRaises(ValueError):collect._suite_result_outcomes(plan,c,obs)
    def inputs(self):
        signature={'primary':{'kind':'behavioral_mismatch','code':'replay_mismatch','traceIndex':0,'stateIndex':5,'action':'write'},'cleanup':{'status':'succeeded'}}
        captured={'lease-reduction-original-bundle':json.dumps({'signature':signature}).encode(),'lease-reduction-candidate-trace':b'trace','lease-reduction-receipt':json.dumps({'candidateCorpusSha256':'a'*64}).encode()}
        result={'schema':'mirrors.lease-reduction-acceptance/v1','status':'reduced','globalMinimumClaim':False,'originalReplayStatus':'reproduced','originalSignature':signature,'candidateSignature':copy.deepcopy(signature),'baseline':suite('passed'),'candidate':suite('mismatch')}
        for key,name in [('originalBundleSha256','lease-reduction-original-bundle'),('candidateTraceSha256','lease-reduction-candidate-trace'),('oracleReceiptSha256','lease-reduction-receipt')]:result[key]=hashlib.sha256(captured[name]).hexdigest()
        for name in ['baseline','candidate']:result[name]['identities']={'corpusDigest':'a'*64}
        return captured,result
    def test_reduction_requires_same_signature_hashes_baseline_and_cleanup(self):
        c,r=self.inputs();c['lease-reduction-acceptance']=json.dumps(r).encode();collect._validate_lease_reduction_acceptance(c)
        for case in ['signature','hash','baseline','cleanup','coordinate','original-replay','minimum','corpus']:
            c,r=self.inputs()
            if case=='signature':r['candidateSignature']['primary']['stateIndex']=6
            if case=='hash':r['candidateTraceSha256']='0'*64
            if case=='baseline':r['baseline']['acceptance']['status']='unmet'
            if case=='cleanup':r['candidate']['cleanup']['status']='failed'
            if case=='coordinate':r['candidate']['failure']['stateIndex']=6
            if case=='original-replay':r['originalReplayStatus']='not_reproduced'
            if case=='minimum':r['globalMinimumClaim']=True
            if case=='corpus':r['candidate']['identities']['corpusDigest']='b'*64
            c['lease-reduction-acceptance']=json.dumps(r).encode()
            with self.subTest(case=case),self.assertRaises(ValueError):collect._validate_lease_reduction_acceptance(c)
