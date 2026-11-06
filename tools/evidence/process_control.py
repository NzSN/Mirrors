"""Bounded native Windows capture using the existing owned tool Job adapter."""
from __future__ import annotations

import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import threading
import time
import types


def windows_job():
    source=Path(__file__).resolve().parents[1]/'deterministic-scheduling/windows_process.py'
    raw=source.read_bytes()
    if len(raw)>256*1024:raise ValueError('Windows job helper exceeds source bound')
    module=types.ModuleType('mirrors_windows_job');module.__file__=str(source)
    exec(compile(raw,str(source),'exec'),module.__dict__)
    return module.WindowsJob()


def capture(argv, cwd, timeout, output_limit, *, forward=False, interruptible=True,
            stop_descendants_on_exit=False, require_clean_exit=False, cleanup_details=None):
    """Capture each stream to its independent bound; retain native exit semantics."""
    owner=windows_job();started=False;readers=[];pipes=[];handlers={};pending=[]
    messages=queue.Queue(maxsize=4);buffers=[bytearray(),bytearray()];exceeded=[False,False]
    ended=set();timed_out=False;returncode=None;unavailable=False;failure=None
    def read(index,pipe):
        try:
            while True:
                block=pipe.read(65536)
                if not block:break
                messages.put((index,block))
        except OSError as error:messages.put((index,error))
        finally:pipe.close();messages.put((index,None))
    def keep(index,block):
        if isinstance(block,OSError):raise block
        if forward:
            sink=[sys.stdout.buffer,sys.stderr.buffer][index]
            try:sink.write(block);sink.flush()
            except (BrokenPipeError,OSError):pass
        capacity=max(0,output_limit-len(buffers[index]));buffers[index].extend(block[:capacity])
        if len(block)>capacity:exceeded[index]=True
    try:
        if interruptible:
            for signum in [signal.SIGINT,signal.SIGTERM,signal.SIGBREAK]:
                handlers[signum]=signal.getsignal(signum)
                signal.signal(signum,lambda received,_frame:pending.append(received))
        with open(os.devnull,'rb') as null:
            pipes=owner.start(argv,cwd,null,env=os.environ)
        started=True
        for index,pipe in enumerate(pipes):
            thread=threading.Thread(target=read,args=(index,pipe),daemon=True);thread.start();readers.append(thread)
        deadline=time.monotonic()+timeout
        while owner.poll() is None or len(ended)<len(readers):
            try:
                index,block=messages.get(timeout=.01)
                if block is None:ended.add(index)
                else:keep(index,block)
            except queue.Empty:pass
            exited=owner.poll()
            if exited is not None and (stop_descendants_on_exit or require_clean_exit):
                if require_clean_exit:
                    settle=min(deadline,time.monotonic()+.1)
                    while owner.active() and time.monotonic()<settle:
                        if owner.members()-{owner.pid}:raise OSError('test exited with live owned descendants')
                        time.sleep(.001)
                    if owner.active():raise OSError('test job exit was not confirmed')
                if cleanup_details is not None:
                    cleanup_details.append({'rootExitCode':exited,'remainingOwnedMembersBeforeCleanup':sorted(owner.members()),
                                            'policy':'owned-compiler-helper-cleanup' if stop_descendants_on_exit else 'strict-test-descendant-check'})
                returncode=exited
                break
            if pending or time.monotonic()>=deadline:
                timed_out=not pending
                owner.terminate(137)
                break
        returncode=owner.poll()
    except OSError as error:
        if started or owner.process is not None:
            failure=error
        else:
            unavailable=True
        block=(type(error).__name__+': '+str(error)+'\n').encode('utf-8','replace')
        buffers[1].extend(block[:output_limit]);exceeded[1]=len(block)>output_limit
    finally:
        try:
            if started or owner.process is not None:
                owner.terminate(137)
                deadline=time.monotonic()+3
                while owner.active() and time.monotonic()<deadline:time.sleep(.01)
                if owner.active():raise OSError('Windows process cleanup incomplete')
                while owner.poll() is None and time.monotonic()<deadline:time.sleep(.001)
                if owner.poll() is None:raise OSError('Windows root process exit was not confirmed')
                if returncode is None:returncode=owner.poll()
        except OSError as error:
            if failure is None:failure=error
        finally:owner.close()
        deadline=time.monotonic()+3
        while len(ended)<len(readers) and time.monotonic()<deadline:
            try:
                index,block=messages.get(timeout=.01)
                if block is None:ended.add(index)
                else:
                    try:keep(index,block)
                    except OSError as error:
                        if failure is None:failure=error
            except queue.Empty:pass
        for reader in readers:
            reader.join(timeout=max(0,deadline-time.monotonic()))
            if reader.is_alive() and failure is None:failure=OSError('Windows capture pipe cleanup incomplete')
        for pipe in pipes:
            if not pipe.closed:pipe.close()
        for signum,handler in handlers.items():signal.signal(signum,handler)
    if failure is not None:raise failure
    return returncode,timed_out,unavailable,bytes(buffers[0]),bytes(buffers[1]),exceeded[0],exceeded[1],signal.Signals(pending[0]).name if pending else None
