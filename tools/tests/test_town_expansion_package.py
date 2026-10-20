"""Small synthetic delivery fixtures; no real town assets or engines run."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from tools.town_generation import package_expansion as pack


class ExpansionPackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name)

    def test_zip_has_only_curated_members_and_every_readback_hash(self):
        source=self.root/"scene.blend"
        source.write_bytes(b"tiny synthetic packed scene")
        (self.root/"secret-not-curated.txt").write_text("must not be copied")
        catalog=pack.Catalog()
        catalog.add(source,"generation/scene/expanded_town.blend")
        catalog.text("README.md","Open generation/scene/expanded_town.blend\n")
        output=self.root/"delivery"
        report=pack.write_archive(catalog,output,{"historical_reports_unmodified":True})
        self.assertEqual(report["status"],"PASS")
        with zipfile.ZipFile(output/pack.ZIP_NAME) as archive:
            self.assertEqual(set(archive.namelist()),{"generation/scene/expanded_town.blend","README.md","bundle_manifest.json"})
            manifest=json.loads(archive.read("bundle_manifest.json"))
            for row in report["archive_members"]:
                data=archive.read(row["path"])
                self.assertEqual(row["bytes"],len(data))
                self.assertEqual(row["sha256"],hashlib.sha256(data).hexdigest())
            self.assertEqual(archive.read("generation/scene/expanded_town.blend"),source.read_bytes())
        self.assertEqual(len(manifest["files"]),2)
        self.assertEqual(pack.sha(output/pack.ZIP_NAME),report["archive"]["sha256"])

    def test_changed_source_cannot_receive_a_success_receipt(self):
        source=self.root/"source.json";source.write_text("original")
        catalog=pack.Catalog();catalog.add(source,"generation/plan.json")
        source.write_text("changed after preflight")
        output=self.root/"delivery"
        with self.assertRaisesRegex(ValueError,"Source changed during packaging"):
            pack.write_archive(catalog,output,{})
        self.assertFalse((output/"package_report.json").exists())
        self.assertEqual(json.loads((output/"package_failure.json").read_text())["status"],"FAIL")

    def test_release_size_gate_runs_before_directory_creation(self):
        catalog=pack.Catalog();catalog.text("README.md","12345")
        output=self.root/"delivery"
        with patch.object(pack,"MAX_BYTES",4),self.assertRaisesRegex(ValueError,"2GB release target"):
            pack.write_archive(catalog,output,{})
        self.assertFalse(output.exists())

    def test_existing_delivery_is_not_overwritten(self):
        output=self.root/"delivery";output.mkdir()
        canary=output/"prior.zip";canary.write_bytes(b"previous delivery")
        with self.assertRaises(FileExistsError):pack.write_archive(pack.Catalog(),output,{})
        self.assertEqual(canary.read_bytes(),b"previous delivery")

    def test_traversal_runtime_and_raw_capture_members_are_rejected(self):
        for name in ("../secret","/absolute","C:/secret","a\\b","a/../b","a//b","scene.blend1","raw.ogv","debug.log","tools/__pycache__/x.pyc","worker/venv/a.py","models/weights.bin"):
            with self.subTest(name=name),self.assertRaises(ValueError):pack.member_name(name)

    def test_member_case_collisions_are_rejected_for_windows_extraction(self):
        catalog=pack.Catalog();catalog.text("README.md","first")
        with self.assertRaisesRegex(ValueError,"Case-colliding"):
            catalog.text("readme.md","second")

    def test_failed_receipt_and_stale_hash_are_rejected(self):
        receipt=self.root/"review.json";receipt.write_text('{"status":"FAIL"}')
        with self.assertRaisesRegex(ValueError,"did not pass"):pack.pass_receipt(receipt)
        source=self.root/"asset.glb";source.write_bytes(b"actual bytes")
        with self.assertRaisesRegex(ValueError,"SHA differs"):
            pack.check_binding({"path":str(source),"bytes":source.stat().st_size,"sha256":"0"*64})

    def test_consumer_proof_must_match_the_curated_viewer_sources(self):
        viewer=self.root/"tools/town_generation/godot_viewer";viewer.mkdir(parents=True)
        script=viewer/"main.gd";script.write_text("extends Node3D\n")
        project=viewer/"project.godot";project.write_text("config_version=5\n")
        report={"status":"PASS","consumer_source_sha256":pack.sha(script),
                "project_sha256":pack.sha(project)}
        with patch.object(pack,"REPO",self.root):
            pack.check_consumer_sources(report)
            for key in ("consumer_source_sha256","project_sha256"):
                for stale in (None,"0"*64):
                    with self.subTest(key=key,stale=stale),self.assertRaisesRegex(ValueError,"used another"):
                        pack.check_consumer_sources(dict(report,**{key:stale}))
            script.write_text("extends Node3D\n# new cutaway gate\n")
            with self.assertRaisesRegex(ValueError,"another consumer source"):
                pack.check_consumer_sources(report)
            current=dict(report,consumer_source_sha256=pack.sha(script))
            project.write_text("config_version=5\n# new renderer settings\n")
            with self.assertRaisesRegex(ValueError,"another viewer project"):
                pack.check_consumer_sources(current)

    def test_curated_relative_source_cannot_escape_root(self):
        inside=self.root/"inputs";inside.mkdir()
        outside=self.root/"secret";outside.write_bytes(b"not an input")
        with self.assertRaisesRegex(ValueError,"escapes its declared root"):
            pack.beneath(inside,"../secret")

    def test_input_and_source_trees_cannot_be_delivery_output(self):
        source=self.root/"generation";source.mkdir()
        for destination in (source,source/"delivery",source.parent,pack.REPO/"art/new-delivery"):
            with self.subTest(destination=destination),self.assertRaises(ValueError):
                pack.fresh_output(destination,[source])


if __name__=="__main__":unittest.main()
