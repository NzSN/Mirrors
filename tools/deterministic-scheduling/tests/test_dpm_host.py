import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from dpm_host import Refusal, classify, owned_process, strict, EvidenceBudget, retained_bytes, validate_exploration, Project, ProcessFailure, reduce
ROOT = Path(__file__).resolve().parents[3]
POLICY = ROOT / '.lake/build/bin/mirrors_dpm'


def typed_check(pairs):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'values.json'
        path.write_text(json.dumps({'schema':'mirrors.dpm-value-check/v1','pairs':pairs}))
        result = subprocess.run([str(POLICY),'_value-check',str(path)],capture_output=True,text=True)
        if result.returncode: raise Refusal(result.stderr)
        return json.loads(result.stdout)['results']


def oracle_context(schedule):
    indices = [0]
    actual = []
    for step in schedule['steps']:
        ignored = step['actor'] == 'spectator'
        if not ignored: actual.append(step)
        indices.append(indices[-1] + (0 if ignored else 1))
    base = ROOT/'Plans/dpm-languages-evidence-20261005/oracles/counter'
    for path in base.glob('*/trace-0.itf.json'):
        trace = json.loads(path.read_text())
        rows = [{'actor':state['parameters']['actor'], 'checkpoint':
                 '$done' if state['action_taken']=='finish' else state['action_taken']}
                for state in trace['states'][1:]]
        if rows == actual and int(trace['states'][0]['count']['#bigint']) == schedule['inputs']['initial']:
            return {'states':trace['states'],'observationStateIndices':indices,
                    'modelActions':[state['action_taken'] for state in trace['states']]}
    raise AssertionError('no independently retained oracle for fixture')


def check_receipt(receipt, candidate=None, signature='counter-count-delta/v1'):
    candidate = candidate or {'schedule':receipt['binding']['executions'][0]['schedule']}
    return classify(receipt, candidate, signature, oracle_context(candidate['schedule']), typed_check)



class DpmHostTests(unittest.TestCase):
    def setUp(self):
        fixture = ROOT/'test/fixtures/deterministic-scheduling/timeline/cpp/counter/mutate.receipt.json'
        self.receipt=json.loads(fixture.read_text())
        self.candidate={'schedule':copy.deepcopy(self.receipt['binding']['executions'][0]['schedule'])}

    def test_actual_retained_mismatch_and_cancelled_cleanup_are_independent(self):
        verdict, signature, ids=check_receipt(self.receipt,self.candidate)
        self.assertEqual(verdict,'step_mismatch');self.assertEqual(signature['delta'],'1');self.assertEqual(len(ids),1)
        self.receipt['binding']['executions'][0]['outcome']='cancelled'
        with self.assertRaises(Refusal): check_receipt(self.receipt,self.candidate)

    def test_receipt_tamper_controls(self):
        for field,value in [('cleanup','incomplete'),('remainingActors',['a']),('executionId',''),
                            ('schedule',{}),('observations',[]),('outcome','timed_out')]:
            with self.subTest(field=field):
                receipt=copy.deepcopy(self.receipt);receipt['binding']['executions'][0][field]=value
                with self.assertRaises(Refusal):check_receipt(receipt,self.candidate)
        for field,value in [('receiptComplete',False),('disposed',False),('disposals',0),('initializations',2)]:
            with self.subTest(field=field):
                receipt=copy.deepcopy(self.receipt);receipt['binding'][field]=value
                with self.assertRaises(Refusal):check_receipt(receipt,self.candidate)

    def test_terminal_and_observation_must_correspond(self):
        for mutate in [lambda r:r.update(comparison='matched',passed=True),
                       lambda r:r.update(peerTerminal='all_steps_done'),
                       lambda r:r['binding']['executions'][0]['observations'][-1].update(state={}),
                       lambda r:r['client'].update(cleanupError='cleanup failed')]:
            receipt=copy.deepcopy(self.receipt);mutate(receipt)
            with self.assertRaises(Refusal):check_receipt(receipt,self.candidate)

    def test_unknown_ambiguous_normalization_refuses(self):
        receipt=copy.deepcopy(self.receipt)
        terminal=json.loads(receipt['peerTerminalRaw']);terminal['actual']['phase']={}
        receipt['peerTerminalRaw']=json.dumps(terminal)
        receipt['binding']['executions'][0]['observations'][-1]['state']=terminal['actual']
        with self.assertRaises(Refusal):check_receipt(receipt,self.candidate)

    def test_duplicate_nonfinite_and_symlink_json_refuse(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'input.json'
            for raw in ['{"x":1,"x":2}','{"x":NaN}','['*65+'0'+']'*65]:
                file.write_text(raw)
                with self.assertRaises(Refusal):strict(file)
            file.write_text('{}');link=Path(directory)/'link';link.symlink_to(file)
            with self.assertRaises(Refusal):strict(link)

    def test_timeout_and_output_bound_stop_actual_owned_process(self):
        for code,timeout,bound in [('import time;time.sleep(10)',0.05,4096),
                                  ('import sys;sys.stdout.write("x"*10000);sys.stdout.flush()',1,100)]:
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(Refusal):owned_process([sys.executable,'-c',code],Path(directory),timeout,bound)

    def test_only_explicit_model_validator_calls_accept_exit_one(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(Refusal):
                owned_process([sys.executable, '-c', 'raise SystemExit(1)'], Path(directory), 2, 4096)
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(owned_process([sys.executable, '-c', 'raise SystemExit(1)'],
                             Path(directory), 2, 4096, accepted_exits=(0, 1)), 1)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(Refusal):
                owned_process([sys.executable, '-c', 'raise SystemExit(2)'],
                              Path(directory), 2, 4096, accepted_exits=(0, 1))

    def test_owned_input_stream_is_bounded_and_delivered_without_a_shell(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); source = root/'public-input.json'
            source.write_text('{"publicModel":true}\n')
            self.assertEqual(owned_process([sys.executable, '-c',
                'import sys;sys.stdout.write(sys.stdin.read())'], root, 2, 4096, input_path=source), 0)
            self.assertEqual((root/'stdout.log').read_text(), source.read_text())

    def test_launcher_refuses_changed_host_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'bin').mkdir();(root/'share/mirrors-dpm').mkdir(parents=True)
            import shutil
            shutil.copy2(POLICY,root/'bin/mirrors-dpm')
            (root/'share/mirrors-dpm/cli.py').write_text('raise RuntimeError("untrusted code ran")\n')
            process=subprocess.run([str(root/'bin/mirrors-dpm'),'doctor'],capture_output=True,text=True)
            self.assertEqual(process.returncode,2);self.assertIn('host artifact differs',process.stderr)
            self.assertNotIn('untrusted code ran',process.stderr)

    def test_public_cli_cannot_override_launcher_policy(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / 'project.json'
            project.write_text('{}\n')
            digest = hashlib.sha256(project.read_bytes()).hexdigest()
            process = subprocess.run([str(POLICY), '--policy', '/bin/false', 'doctor',
                '--project', str(project), '--project-sha256', digest], capture_output=True, text=True)
            self.assertEqual(process.returncode, 2)
            self.assertIn('usage: mirrors-dpm', process.stderr)
            self.assertNotIn('project admission:', process.stderr)


class CancellationOwnershipTests(unittest.TestCase):
    def control(self, scenario):
        controller = Path(__file__).with_name('cancellation_control.py')
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, '-I', '-S', '-B', str(controller),
                '--source', str(ROOT/'tools/deterministic-scheduling'),
                '--out', str(Path(directory)/'controls'), '--scenario', scenario],
                capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            row = json.loads(result.stdout)['rows'][0]
        self.assertIsNone(row['runnerStateAfterHostExit'], row)
        self.assertIsNone(row['runnerStateAfterControllerCleanup'], row)
        self.assertIsNone(row['hostStateAfterControllerCleanup'], row)
        self.assertTrue(row['allControllerChildrenReaped'])
        self.assertFalse(row['controllerReapedRunner'], 'host must reap its runner before returning')
        self.assertIn('runner-ready', row['stdoutLog'])
        self.assertIn('runner-error-log', row['stderrLog'])
        final = row['hostResult']
        self.assertTrue(final['handlersRestored'])
        self.assertTrue(final['maskRestored'])
        self.assertTrue(final['ownerRegistrationRestored'])
        self.assertEqual(final['openLogDescriptorsAfterReturn'], [])
        return row, final

    def refused(self, scenario, primary):
        row, result = self.control(scenario)
        self.assertEqual(row['hostExit'], 2)
        self.assertEqual(result['exception'], 'ProcessFailure')
        self.assertTrue(result['message'].startswith(primary + '; '), result)
        self.assertEqual(result['accounting']['processCleanup'], 'confirmed')
        self.assertEqual(result['accounting']['retainedRequestBytes'], result['retainedBytesAfterReturn'])
        self.assertEqual(result['accounting']['requestOvershoot'], 0)

    def test_normal_execution_reaps_and_restores_signal_state(self):
        row, result = self.control('normal')
        self.assertEqual(row['hostExit'], 0)
        self.assertEqual(result['result'], 'returned')

    def test_single_execution_cancellation_reaps_and_accounts(self):
        self.refused('single', 'operation cancelled')

    def test_repeated_cancellation_cannot_interrupt_cleanup(self):
        self.refused('repeated', 'operation cancelled')

    def test_first_cancellation_during_timeout_cleanup_preserves_timeout(self):
        self.refused('timeout-first', 'runner timeout')

    def test_first_cancellation_during_normal_finalization_refuses_after_cleanup(self):
        self.refused('finalization-first', 'operation cancelled')

    def test_first_cancellation_at_timeout_cleanup_entry_preserves_timeout(self):
        self.refused('cleanup-entry-timeout-first', 'runner timeout')

    def test_repeated_cancellation_at_cleanup_entry_cannot_skip_cleanup(self):
        self.refused('cleanup-entry-repeated', 'operation cancelled')


class PurePolicyTests(unittest.TestCase):
    def project(self):
        identity={k:'a'*64 for k in ['modelSemanticDigest','mappingSha256','implementationSha256']}
        schedule={'schema':'mirrors.checkpoint-schedule/v1','profile':'mirrorcpp.cooperative-checkpoints/v1',
                  'identity':identity,'inputs':{},'steps':[{'actor':'a','checkpoint':'read'},{'actor':'a','checkpoint':'$done'}]}
        ref={'path':'artifact','sha256':'b'*64}
        return {'schema':'mirrors.dpm-project/v2','profile':schedule['profile'],'identity':identity,
            'explorerIdentity':None,'command':{'kind':'native','executable':'runner','args':[]},'artifacts':[ref],'chains':[{'actor':'a','checkpoints':['read','$done']}],
            'baseline':'base','candidates':[{'id':'base','inputRank':0,'schedule':schedule,'oracle':ref,'provenance':ref}],
            'signature':'exact-terminal/v1','limits':{'attempts':8,'timeoutMs':1000,'totalTimeoutMs':5000,'outputBytes':10000,'totalOutputBytes':1048576}}

    def plan(self,project):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'project.json';path.write_text(json.dumps(project))
            return subprocess.run([str(POLICY),'_plan',str(path)],capture_output=True,text=True)

    def test_actual_v1_project_has_reprepare_diagnostic(self):
        legacy=json.loads((ROOT/'Plans/dpm-f3-f5-evidence-20261013/input-projects/prebuilt/cpp.json').read_text())
        process=self.plan(legacy)
        self.assertEqual(process.returncode,2)
        self.assertIn('reprepare as mirrors.dpm-project/v2',process.stderr)

    def test_pure_admission_and_cost(self):
        process=self.plan(self.project());self.assertEqual(process.returncode,0,process.stderr)
        self.assertEqual(json.loads(process.stdout)['order'],[{'id':'base','cost':[1,0,0,2]}])

    def test_actor_chains_and_closed_schema(self):
        transforms=[lambda p:p.update(schema='mirrors.dpm-project/v1'),
                    lambda p:p.update(command=['runner']),
                    lambda p:p['command'].update(kind='unknown'),
                    lambda p:p['command']['args'].append({'literal':'x','artifact':'x'}),
                    lambda p:p['command']['args'].append({'literal':'x\x00y'}),
                    lambda p:p['limits'].update(totalOutputBytes=1),
                    lambda p:p['limits'].update(totalOutputBytes=65536+8*1024),
                    lambda p:p.update(explorerIdentity={}),lambda p:p.update(unknown=True),lambda p:p['identity'].update(modelSemanticDigest='bad'),
                    lambda p:p['candidates'][0]['schedule']['steps'].reverse(),
                    lambda p:p['candidates'][0]['schedule']['steps'].append({'actor':'a','checkpoint':'read'}),
                    lambda p:p['candidates'][0]['schedule']['steps'][0].update(actor='foreign'),
                    lambda p:p['chains'].append(p['chains'][0]),lambda p:p['candidates'].append(p['candidates'][0]),
                    lambda p:p['limits'].update(attempts=0),lambda p:p.update(baseline='missing')]
        for transform in transforms:
            project=self.project();transform(project)
            with self.subTest(project=project):self.assertEqual(self.plan(project).returncode,2)

    def test_complete_two_actor_interleavings_have_correct_costs(self):
        import itertools
        project=self.project();project['chains'].append({'actor':'b','checkpoints':['read','$done']})
        candidates=[]
        for i, positions in enumerate(itertools.combinations(range(4),2)):
            counters={'a':0,'b':0};steps=[]
            for position in range(4):
                actor='a' if position in positions else 'b'
                steps.append({'actor':actor,'checkpoint':['read','$done'][counters[actor]]});counters[actor]+=1
            candidate=copy.deepcopy(project['candidates'][0]);candidate['id']='c'+str(i);candidate['schedule']['steps']=steps
            candidates.append(candidate)
        project['candidates']=candidates;project['baseline']='c0'
        result=self.plan(project);self.assertEqual(result.returncode,0,result.stderr)
        rows=json.loads(result.stdout)['order'];self.assertEqual(len(rows),6)
        self.assertEqual(sorted(r['cost'][2] for r in rows),[0,0,1,1,2,2])


class EvidenceRegressionTests(unittest.TestCase):
    def fixtures(self, outcome='ok'):
        base = ROOT/'test/fixtures/deterministic-scheduling/timeline'
        yield 'cpp', json.loads((base/'cpp/counter'/f'{outcome}.receipt.json').read_text())
        for language in ['ecma','rust']:
            yield language, json.loads((base/language/'counter'/f'serial-{outcome}'/'receipt.json').read_text())

    def test_all_three_actual_full_matches_and_early_mismatches(self):
        for mode in ['ok','mutate']:
            for language, receipt in self.fixtures(mode):
                with self.subTest(language=language, mode=mode):
                    self.assertEqual(check_receipt(receipt)[0], 'matched' if mode=='ok' else 'step_mismatch')

    def test_all_three_event_observation_and_completion_mutants(self):
        mutations = [
            lambda e:e.update(events=[],observations=[{}],outcome='cancelled'),
            lambda e:e['events'].pop(),
            lambda e:e['events'][0].update(ordinal=True),
            lambda e:e['events'][1].update(step=1),
            lambda e:e['events'][0].update(kind='arrival'),
            lambda e:e['events'][2].update(checkpoint='$start'),
            lambda e:e['events'][1].update(actor='foreign'),
            lambda e:e['events'][1].update(operation='foreign'),
            lambda e:e['events'][1].update(checkpoint='$done'),
            lambda e:e['observations'][1].update(afterSteps=True),
            lambda e:e['observations'][1].update(afterSteps=2),
            lambda e:e['observations'][0].pop('state'),
            lambda e:e['actors'].pop(),
            lambda e:e['actors'].append(e['actors'][0]),
            lambda e:e.update(generation=True),
            lambda e:e.update(passed=1),
            lambda e:e.update(scheduleCompleted=1),
            lambda e:e.update(outcome='cancelled'),
            lambda e:e['cleanupAttempts'][-1].update(remainingActors=['a']),
            lambda e:e['observations'][0]['state'].update(count=True),
        ]
        for language, original in self.fixtures():
            candidate={'schedule':copy.deepcopy(original['binding']['executions'][0]['schedule'])}
            for index, mutation in enumerate(mutations):
                receipt=copy.deepcopy(original);mutation(receipt['binding']['executions'][0])
                with self.subTest(language=language,mutation=index), self.assertRaises(Refusal):
                    check_receipt(receipt,candidate)
            receipt=copy.deepcopy(original)
            receipt['binding']['executions'][0]['schedule']['identity']['implementationSha256']='0'*64
            with self.assertRaises(Refusal):check_receipt(receipt,candidate)

    def test_terminal_client_and_typed_map_mutants(self):
        for language, original in self.fixtures('mutate'):
            for location in ['terminal','client']:
                receipt=copy.deepcopy(original)
                if location=='terminal':
                    terminal=json.loads(receipt['peerTerminalRaw']);terminal['expected']['count']={'#bigint':'900'}
                    receipt['peerTerminalRaw']=json.dumps(terminal)
                else:receipt['client']['actual']['count']=True
                with self.subTest(language=language,location=location), self.assertRaises(Refusal):check_receipt(receipt)
            receipt=copy.deepcopy(original)
            receipt['binding']['executions'][0]['observations'][0]['state']['phase']['#map'].append(['a',{'#bigint':'0'}])
            with self.assertRaises(Refusal):check_receipt(receipt)

    def test_map_order_equivalence_and_spectator_offsets(self):
        for language, receipt in self.fixtures():
            receipt['binding']['executions'][0]['observations'][0]['state']['phase']['#map'].reverse()
            self.assertEqual(check_receipt(receipt)[0],'matched')
        base=ROOT/'Plans/dpm-f3-f5-evidence-20261013/installed'
        for language in ['cpp','ecma','rust']:
            receipt=json.loads((base/language/'mismatch/receipt.json').read_text())
            self.assertEqual(check_receipt(receipt)[0],'step_mismatch')
            if language=='ecma':
                receipt['client']['stateIndex']+=1
                with self.assertRaises(Refusal):check_receipt(receipt)

    def test_materialization_uses_exact_json_identity(self):
        original=next(self.fixtures())[1]
        candidate={'id':'base','schedule':copy.deepcopy(original['binding']['executions'][0]['schedule']),
                   'oracle':{'path':'oracle','sha256':'a'*64},'provenance':{'path':'binding','sha256':'b'*64}}
        materialized={key:copy.deepcopy(candidate[key]) for key in ['schedule','oracle','provenance']}
        materialized['schedule']['inputs']['initial']=False
        project=Project.__new__(Project);project.candidates={'base':candidate}
        project.request=lambda *args:materialized
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(Refusal,'materializer changed'):
                project.replay('base',Path(directory)/'run',0)

    def test_replay_ids_are_fresh_across_independent_generation_one_processes(self):
        receipt=next(self.fixtures('mutate'))[1]
        candidate={'id':'base','schedule':copy.deepcopy(receipt['binding']['executions'][0]['schedule']),
                   'oracle':{'path':'oracle','sha256':'a'*64},'provenance':{'path':'binding','sha256':'b'*64}}
        project=Project.__new__(Project);project.candidates={'base':candidate}
        project.data={'signature':'counter-count-delta/v1'};project.seen=set()
        project.oracles={'base':oracle_context(candidate['schedule'])}
        project.values=lambda pairs,deadline:typed_check(pairs)
        project.request=lambda operation,*args:receipt if operation=='replay' else {
            key:candidate[key] for key in ['schedule','oracle','provenance']}
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            self.assertEqual(project.replay('base',root/'one',0)[0],'step_mismatch')
            with self.assertRaisesRegex(Refusal,'execution identity reused'):project.replay('base',root/'two',0)
            receipt['binding']['executions'][0]['executionId']+='new'
            self.assertEqual(project.replay('base',root/'three',0)[0],'step_mismatch')

    def test_reducer_does_not_equate_boolean_and_integer_failures(self):
        original=next(self.fixtures())[1]
        results=[]
        for value in [True,1]:
            receipt=copy.deepcopy(original);execution=receipt['binding']['executions'][0]
            expected=copy.deepcopy(execution['observations'][1]['state'])
            actual=copy.deepcopy(expected);actual['count']=value
            execution.update(events=execution['events'][:2], observations=execution['observations'][:2],
                             passed=False, scheduleCompleted=False)
            execution['observations'][1]['state']=actual
            receipt.update(comparison='step_mismatch',passed=False,peerTerminal='step_mismatch',
                peerTerminalRaw=json.dumps({'proto_step':'step_mismatch','expected':expected,'actual':actual}),
                client={'status':'failed','kind':'step_mismatch','expected':expected,'actual':actual})
            results.append(check_receipt(receipt,signature='exact-terminal/v1'))
        class Budget:
            reserve=0
            def audit(self):pass
        class Baseline:
            data={'limits':{'totalTimeoutMs':1000},'baseline':'base'}
            budget=Budget()
            def replay(self,*args):return results.pop(0)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(Refusal,'not a stable failure'):reduce(Baseline(),Path(directory))

    def test_final_interval_mismatch_preserves_completed_execution(self):
        for language, receipt in self.fixtures():
            execution=receipt['binding']['executions'][0]
            expected=copy.deepcopy(execution['observations'][-1]['state'])
            actual=copy.deepcopy(expected);actual['count']={'#bigint':'9'}
            execution['observations'][-1]['state']=actual
            receipt.update(comparison='step_mismatch',passed=False,peerTerminal='step_mismatch',
                peerTerminalRaw=json.dumps({'proto_step':'step_mismatch','expected':expected,'actual':actual}),
                client={'status':'failed','kind':'step_mismatch','expected':expected,'actual':actual,
                        'action':'finish','stateIndex':len(execution['observations'])-1})
            self.assertEqual(check_receipt(receipt,signature='exact-terminal/v1')[0],'step_mismatch')
            receipt['client']['action']='$done'
            with self.assertRaises(Refusal):check_receipt(receipt,signature='exact-terminal/v1')

    def test_initial_observation_mismatch_is_exact_terminal_only(self):
        for language, receipt in self.fixtures('mutate'):
            execution=receipt['binding']['executions'][0]
            expected=copy.deepcopy(execution['observations'][0]['state'])
            actual=copy.deepcopy(expected);actual['count']={'#bigint':'100'}
            execution.update(events=[],observations=[{'afterSteps':0,'state':actual}])
            receipt['peerTerminalRaw']=json.dumps({'proto_step':'step_mismatch','expected':expected,'actual':actual})
            receipt['client']={'status':'failed','kind':'step_mismatch','message':'initial state mismatch',
                               'expected':expected,'actual':actual}
            if language=='ecma':receipt['client'].update(action='init',stateIndex=0,traceIndex=0)
            with self.subTest(language=language):
                verdict,fingerprint,_=check_receipt(receipt,signature='exact-terminal/v1')
                self.assertEqual(verdict,'step_mismatch');self.assertIsNone(fingerprint['checkpoint'])
                with self.assertRaises(Refusal):check_receipt(receipt)
                wrong=copy.deepcopy(receipt);wrong['client']['action']='write'
                with self.assertRaises(Refusal):check_receipt(wrong,signature='exact-terminal/v1')
                wrong=copy.deepcopy(receipt);wrong['client']['stateIndex']=1
                with self.assertRaises(Refusal):check_receipt(wrong,signature='exact-terminal/v1')
                wrong=copy.deepcopy(receipt);wrong['client']['actual']=expected
                with self.assertRaises(Refusal):check_receipt(wrong,signature='exact-terminal/v1')
                wrong=copy.deepcopy(receipt)
                terminal=json.loads(wrong['peerTerminalRaw']);terminal['expected']['count']={'#bigint':'99'}
                wrong['peerTerminalRaw']=json.dumps(terminal)
                with self.assertRaises(Refusal):check_receipt(wrong,signature='exact-terminal/v1')

    def test_client_action_uses_admitted_model_alias_in_all_profiles(self):
        for language, receipt in self.fixtures('mutate'):
            candidate={'schedule':receipt['binding']['executions'][0]['schedule']}
            context=oracle_context(candidate['schedule'])
            after=receipt['binding']['executions'][0]['observations'][-1]['afterSteps']
            index=context['observationStateIndices'][after]
            context['modelActions'][index]='StoreAlias'
            context['states'][index]['action_taken']='StoreAlias'
            receipt['client']['action']='StoreAlias'
            with self.subTest(language=language):
                self.assertEqual(classify(receipt,candidate,'counter-count-delta/v1',context,typed_check)[0],'step_mismatch')
                receipt['client']['action']='write'
                with self.assertRaises(Refusal):classify(receipt,candidate,'counter-count-delta/v1',context,typed_check)

    def test_complete_exploration_cannot_erase_rows_or_contradict_denominators(self):
        base=ROOT/'Plans/dpm-f3-f5-evidence-20261013/installed'
        def empty_review_repro(receipt):
            receipt.update(runs=[],attemptedRuns=0,eligibleRuns=0,completedRuns=0)
        def empty_consistent_counts(receipt):
            receipt.update(runs=[],attemptedRuns=0,eligibleRuns=0,completedRuns=0,
                           eligibleRunsLowerBound=0,enumeratedScheduleShapes=0,categories={})
        def missing_run_with_adjusted_totals(receipt):
            receipt['runs'].pop()
            receipt.update(attemptedRuns=39,eligibleRuns=39,completedRuns=39,categories={'passed':39})
        mutations=[empty_review_repro,empty_consistent_counts,missing_run_with_adjusted_totals,
                   lambda r:r['runs'].pop(),
                   lambda r:r.update(eligibleRunsLowerBound=39),
                   lambda r:r.update(enumeratedScheduleShapes=19),
                   lambda r:r.update(inputAssignments=1),
                   lambda r:r.update(inputAssignments=True),
                   lambda r:r.update(categories={'passed':39,'failed':1}),
                   lambda r:r.update(categories={'passed':True}),
                   lambda r:r.update(stopReason='time_budget'),
                   lambda r:r.pop('stopReason'),
                   lambda r:r.update(firstFailure={'ordinal':0}),
                   lambda r:r.update(denominatorKnown=False)]
        for language in ['cpp','ecma','rust']:
            original=json.loads((base/language/'sdk-exploration/receipt.json').read_text())
            identity=original['runs'][0]['schedule']['identity']
            for ordinal,mutation in enumerate(mutations):
                receipt=copy.deepcopy(original);mutation(receipt)
                with self.subTest(language=language,mutation=ordinal), self.assertRaises(Refusal):
                    validate_exploration(receipt,typed_check,expected_identity=identity)

    def test_local_exploration_uses_shared_validator_and_global_ids(self):
        base=ROOT/'Plans/dpm-f3-f5-evidence-20261013/installed'
        for language in ['cpp','ecma','rust']:
            receipt=json.loads((base/language/'sdk-exploration/receipt.json').read_text())
            identity=receipt['runs'][0]['schedule']['identity']
            seen=set()
            validate_exploration(receipt,typed_check,seen,expected_identity=identity)
            self.assertEqual(len(seen),40)
            with self.assertRaises(Refusal):validate_exploration(receipt,typed_check,seen,expected_identity=identity)
            changed=copy.deepcopy(receipt);changed['runs'][0]['execution']['events']=[]
            with self.assertRaises(Refusal):validate_exploration(changed,typed_check,expected_identity=identity)
            with self.assertRaises(Refusal):validate_exploration(receipt,typed_check,expected_identity={})


class OutputAndImportRegressionTests(unittest.TestCase):
    def test_exact_raw_receipt_reproduction_and_post_exit_response(self):
        for code in [
            "from pathlib import Path;Path('sdk-receipt.json').write_bytes(b'x'*1048576);Path('response.json').write_text('{}')",
            "from pathlib import Path;Path('response.json').write_bytes(b'x'*101)",
            "from pathlib import Path;Path('nested').mkdir();Path('nested/raw').write_bytes(b'x'*101)"]:
            with tempfile.TemporaryDirectory() as directory:
                root=Path(directory)
                with self.assertRaisesRegex(Refusal,'output bound exceeded'):
                    owned_process([sys.executable,'-I','-S','-B','-c',code],root,5,100)
                self.assertGreater(retained_bytes(root),100)
                if (root/'sdk-receipt.json').exists():
                    # The owner can stop a direct write before its requested
                    # 1 MiB finishes. Preserve and measure those partial bytes.
                    size=(root/'sdk-receipt.json').stat().st_size
                    self.assertGreater(size,100)
                    self.assertLessEqual(size,1048576)

    def test_exact_limit_duplicates_and_aggregate_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);budget=EvidenceBudget(root,150,reserve=0)
            for index in range(2):
                request=root/str(index);request.mkdir()
                code="from pathlib import Path;Path('raw').write_bytes(b'x'*50);Path('response.json').write_bytes(b'x'*50)"
                if index==0:owned_process([sys.executable,'-c',code],request,5,100,budget)
                else:
                    with self.assertRaises(Refusal):owned_process([sys.executable,'-c',code],request,5,100,budget)
            self.assertEqual(retained_bytes(root),200)

    def test_stream_flood_is_capped_and_descendant_writer_is_stopped(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            with self.assertRaises(ProcessFailure) as failed:
                owned_process([sys.executable,'-c',"import os;os.write(1,b'x'*1048576);os.write(2,b'y'*1048576)"],root,5,100)
            self.assertTrue(failed.exception.accounting['logsTruncated'])
            self.assertGreater(failed.exception.accounting['observedDiscardedBytes'],0)
            self.assertEqual(failed.exception.accounting['processCleanup'],'confirmed')
            self.assertLessEqual(retained_bytes(root),100)
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            code="import os,time;from pathlib import Path;pid=os.fork();exec(\"time.sleep(5);Path('late-output').write_text('late')\") if pid==0 else None"
            with self.assertRaisesRegex(Refusal,'live owned descendants'):
                owned_process([sys.executable,'-c',code],root,2,1000)
            self.assertFalse((root/'late-output').exists())

    def test_host_copies_and_final_report_reserve_are_charged(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);budget=EvidenceBudget(root,100,reserve=20)
            budget.write(root/'receipt.json',{'x':'y'*70})
            with self.assertRaises(Refusal):budget.write(root/'copy.json',{'x':'y'*70})
            self.assertFalse((root/'copy.json').exists())
            budget.write(root/'result.json',{'status':'done'},final=True)
            self.assertEqual(budget.audit(final=True),retained_bytes(root))
            self.assertLessEqual(retained_bytes(root),100)

    def test_failed_raw_overshoot_is_preserved_and_measured(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);project=Project.__new__(Project)
            project.data={'limits':{'totalOutputBytes':100000,'attempts':1}}
            project.digest='a'*64;project.begin(root)
            raw=root/'sdk-receipt.json';raw.write_bytes(b'x'*120000)
            with self.assertRaises(Refusal) as failure:project.budget.audit()
            project.record_failure(failure.exception)
            report=json.loads((root/'result.json').read_text())
            self.assertEqual(report['status'],'incomplete')
            self.assertEqual(raw.stat().st_size,120000)
            self.assertEqual(report['retainedBytes'],retained_bytes(root))
            self.assertEqual(report['observedOvershoot'],retained_bytes(root)-100000)

    def test_nonregular_output_refuses(self):
        for code in ["import os;os.symlink('/etc/passwd','foreign')", "import os;os.mkfifo('fifo')"]:
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(Refusal):owned_process([sys.executable,'-c',code],Path(directory),5,1000)

    def test_adjacent_host_source_and_bytecode_never_execute(self):
        import shutil, py_compile, importlib.util, struct
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=ROOT/'tools/deterministic-scheduling'
            for name in ['cli.py','dpm_host.py']:shutil.copy2(source/name,root/name)
            marker=root/'marker'
            (root/'hashlib.py').write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("injected")')
            evil=root/'evil.py';evil.write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("pyc")')
            cache=Path(importlib.util.cache_from_source(str(root/'dpm_host.py')))
            cache.parent.mkdir()
            py_compile.compile(str(evil),cfile=str(cache))
            # Make the poisoned cache valid for the unchanged admitted source.
            raw=bytearray(cache.read_bytes());metadata=(root/'dpm_host.py').stat()
            raw[8:16]=struct.pack('<II',int(metadata.st_mtime),metadata.st_size)
            cache.write_bytes(raw)
            pins={'dpm_host.py':hashlib.sha256((root/'dpm_host.py').read_bytes()).hexdigest()}
            completed=subprocess.run([sys.executable,'-I','-S','-B',str(root/'cli.py'),
                '--host-identities',json.dumps(pins),'--policy',str(POLICY),'doctor'],capture_output=True)
            self.assertEqual(completed.returncode,2);self.assertFalse(marker.exists())

    def test_typed_python_command_blocks_adjacent_json(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);marker=root/'marker'
            runner=root/'counter_runner.py';shutil.copy2(ROOT/'tools/deterministic-scheduling/apps/counter_runner.py',runner)
            application=root/'application.json';application.write_text('{}')
            (root/'json.py').write_text('from pathlib import Path;Path('+repr(str(marker))+').write_text("injected")')
            project=PurePolicyTests().project();python=Path(sys.executable).resolve()
            project['command']={'kind':'python-isolated','executable':str(python),'script':runner.name,
                                'args':[{'artifact':application.name}]}
            project['artifacts']=[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
                                  for p in [python,runner,application]]
            for candidate in project['candidates']:
                candidate['oracle']=candidate['provenance']=project['artifacts'][-1]
            path=root/'project.json';path.write_text(json.dumps(project))
            selected=Project(path,hashlib.sha256(path.read_bytes()).hexdigest(),POLICY)
            self.assertEqual(selected.command[1:4],['-I','-S','-B'])
            result=subprocess.run(selected.command,capture_output=True)
            self.assertEqual(result.returncode,2);self.assertFalse(marker.exists())


if __name__=='__main__':unittest.main()
