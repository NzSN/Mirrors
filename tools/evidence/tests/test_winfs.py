"""Actual Windows ACL, file-ID, reparse and atomic-publication regressions."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))


@unittest.skipUnless(os.name=='nt','requires native Windows filesystem handles and ACLs')
class NativeStoreTests(unittest.TestCase):
    def setUp(self):
        import winfs
        self.fs=winfs
        self.temporary=tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name)/'private'
        winfs.create_directory(self.root)

    def test_named_file_ids_are_real_and_distinct(self):
        f=self.fs
        for name in ['one','two']:f.write_exclusive(self.root/name,b'same')
        root=f.open_directory(self.root)
        try:
            one=f.stat_at(root,'one');two=f.stat_at(root,'two')
            self.assertNotEqual(one.st_ino,0);self.assertNotEqual(one.st_ino,two.st_ino)
            self.assertEqual(f.read_at(root,'one')[0],b'same')
        finally:os.close(root)

    def test_pinned_root_cannot_redirect_to_a_replacement(self):
        f=self.fs;f.write_exclusive(self.root/'record',b'original')
        outside=Path(self.temporary.name)/'outside';outside.mkdir();(outside/'record').write_bytes(b'foreign')
        root=f.open_directory(self.root)
        moved=self.root.with_name('moved')
        try:
            self.root.rename(moved)
            result=subprocess.run(['cmd.exe','/d','/c','mklink','/J',str(self.root),str(outside)],capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            try:
                self.assertEqual(f.read_at(root,'record')[0],b'original')
                with self.assertRaises((OSError,ValueError)):f.read_regular(self.root/'record')
                with self.assertRaises((OSError,ValueError)):f.write_exclusive(self.root/'foreign',b'redirected')
                self.assertFalse((outside/'foreign').exists())
            finally:self.root.rmdir()
        finally:os.close(root)

    def test_private_acl_can_be_prepared_and_verified_without_chmod(self):
        f=self.fs;path=self.root/'record';path.write_bytes(b'private')
        f.set_private(path);f.check_private(path)
        f.check_private(self.root)
        self.assertEqual(f.read_regular(path)[0],b'private')

    def test_ambiguous_windows_names_refuse_before_creation(self):
        root=self.fs.open_directory(self.root)
        try:
            for name in ['record:alternate','NUL','COM1.txt','trailing.','trailing ','a\\b']:
                with self.subTest(name=name),self.assertRaises(ValueError):
                    self.fs.open_at(root,name,create=True,exclusive=True,write=True)
        finally:os.close(root)
        self.assertEqual(list(self.root.iterdir()),[])

    def test_unicode_names_and_exclusive_publication_race(self):
        f=self.fs
        unicode_name='记录-😀';f.write_exclusive(self.root/unicode_name,b'utf8-name')
        self.assertEqual(f.read_regular(self.root/unicode_name)[0],b'utf8-name')
        for name in ['left','right']:f.write_exclusive(self.root/name,name.encode())
        barrier=threading.Barrier(2);outcomes=[]
        def publish(name):
            barrier.wait()
            try:f.publish_exclusive(self.root,name,'committed');outcomes.append('committed')
            except FileExistsError:outcomes.append('refused')
        threads=[threading.Thread(target=publish,args=(name,)) for name in ['left','right']]
        for thread in threads:thread.start()
        for thread in threads:thread.join(timeout=5);self.assertFalse(thread.is_alive())
        self.assertEqual(sorted(outcomes),['committed','refused'])
        self.assertIn(f.read_regular(self.root/'committed')[0],[b'left',b'right'])
        f.fsync_directory(self.root)


if __name__=='__main__':unittest.main()
