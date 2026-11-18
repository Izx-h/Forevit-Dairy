from __future__ import annotations

import hashlib
import os
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from forevit_worker.extraction import TextUnit, extract_document, split_units
from forevit_worker.supabase import Settings
from forevit_worker.worker import Worker, _valid_ids, retry_delay_seconds


class ChunkingTests(unittest.TestCase):
    def test_source_metadata_survives_split(self):
        text = "word " * 30
        chunks = split_units([TextUnit(text, 3, "Results")], chunk_chars=40, overlap_chars=8)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(c.page_no == 3 and c.section_label == "Results" for c in chunks))
        self.assertTrue(all(len(c.content) <= 40 for c in chunks))
        self.assertEqual([c.chunk_no for c in chunks], list(range(len(chunks))))

    def test_reject_invalid_overlap(self):
        with self.assertRaises(ValueError):
            split_units([TextUnit("text")], chunk_chars=10, overlap_chars=10)

    def test_plain_text_extraction_and_page_breaks(self):
        result = extract_document(b"Alpha\fBeta", "note.txt", "text/plain")
        self.assertEqual([u.text for u in result], ["Alpha", "Beta"])


class SafetyTests(unittest.TestCase):
    def test_missing_supabase_secrets_fails_before_worker_construction(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "SUPABASE_URL"):
                Settings.from_env()

    def test_ids_accept_only_uuid_values(self):
        ids = _valid_ids(["d9428888-122b-11e1-b85c-61cd3cbb3210", "x),or(id.eq.anything", "d9428888-122b-11e1-b85c-61cd3cbb3210"])
        self.assertEqual(ids, ["d9428888-122b-11e1-b85c-61cd3cbb3210"])

    def test_ai_processing_is_disabled_unless_explicitly_enabled(self):
        env = {"SUPABASE_URL": "https://example.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "test-only"}
        with patch.dict(os.environ, env, clear=True):
            self.assertFalse(Settings.from_env().ai_enabled)
        with patch.dict(os.environ, {**env, "AI_ENABLED": "true"}, clear=True):
            self.assertTrue(Settings.from_env().ai_enabled)
        with patch.dict(os.environ, {**env, "AI_ENABLED": "TRUE"}, clear=True):
            self.assertFalse(Settings.from_env().ai_enabled)

    def test_disabled_ai_worker_does_not_claim_jobs(self):
        db = Mock()
        worker = Worker(Settings("https://example.supabase.co", "test-only", "worker-id"), db=db)
        self.assertFalse(worker.process_one_ai_job())
        db.rpc_claim.assert_not_called()

    def test_lease_check_requires_current_processing_token(self):
        db = Mock()
        db.select.return_value = []
        worker = Worker(Settings("https://example.supabase.co", "test-only", "worker-id"), db=db)
        job = {"id": "d9428888-122b-11e1-b85c-61cd3cbb3210", "lease_token": "d9428888-122b-11e1-b85c-61cd3cbb3211"}
        self.assertFalse(worker._owns_lease("ai_jobs", job))
        db.select.assert_called_once_with("ai_jobs", params={
            "id": "eq.d9428888-122b-11e1-b85c-61cd3cbb3210",
            "status": "eq.processing",
            "lease_token": "eq.d9428888-122b-11e1-b85c-61cd3cbb3211",
            "limit": "1",
        })

    def test_failed_job_update_is_fenced_by_lease_token(self):
        db = Mock()
        db.update_matching.return_value = False
        worker = Worker(Settings("https://example.supabase.co", "test-only", "worker-id"), db=db)
        job = {
            "id": "d9428888-122b-11e1-b85c-61cd3cbb3210",
            "lease_token": "d9428888-122b-11e1-b85c-61cd3cbb3211",
            "attempts": 1,
            "max_attempts": 5,
        }
        worker._mark_failed("ai_jobs", job, "provider_request_failed")
        db.update_matching.assert_called_once()
        self.assertEqual(db.update_matching.call_args.args[1], {
            "id": "eq.d9428888-122b-11e1-b85c-61cd3cbb3210",
            "status": "eq.processing",
            "lease_token": "eq.d9428888-122b-11e1-b85c-61cd3cbb3211",
        })
        self.assertIsNone(db.update_matching.call_args.args[2]["lease_token"])

    def test_document_chunk_write_carries_claim_lease_token(self):
        job_id = "d9428888-122b-11e1-b85c-61cd3cbb3210"
        lease_token = "d9428888-122b-11e1-b85c-61cd3cbb3211"
        project_id = "d9428888-122b-11e1-b85c-61cd3cbb3212"
        version_id = "d9428888-122b-11e1-b85c-61cd3cbb3213"
        db = Mock()
        db.select.side_effect = [
            [{"id": job_id}],
            [{"id": version_id, "byte_size": 4, "sha256_hex": hashlib.sha256(b"test").hexdigest(),
              "storage_bucket": "private", "storage_path": "object", "file_name": "note.txt",
              "mime_type": "text/plain"}],
            [{"id": job_id}],
        ]
        db.storage_download.return_value = b"test"
        chunk = Mock(chunk_no=0, page_no=1, section_label="Results", content="test text", metadata={})
        worker = Worker(Settings("https://example.supabase.co", "test-only", "worker-id"), db=db)
        job = {"id": job_id, "lease_token": lease_token, "project_id": project_id,
               "document_version_id": version_id, "job_type": "extract"}
        with patch("forevit_worker.worker.extract_document", return_value=[Mock()]), \
             patch("forevit_worker.worker.split_units", return_value=[chunk]):
            worker._process_document(job)
        row = db.insert.call_args.args[1][0]
        self.assertEqual(row["processing_job_id"], job_id)
        self.assertEqual(row["processing_lease_token"], lease_token)

    def test_ai_side_effect_writes_carry_claim_lease_token(self):
        job_id = "d9428888-122b-11e1-b85c-61cd3cbb3210"
        lease_token = "d9428888-122b-11e1-b85c-61cd3cbb3211"
        project_id = "d9428888-122b-11e1-b85c-61cd3cbb3212"
        actor = "d9428888-122b-11e1-b85c-61cd3cbb3213"
        conversation_id = "d9428888-122b-11e1-b85c-61cd3cbb3214"
        report_id = "d9428888-122b-11e1-b85c-61cd3cbb3215"
        source_id = "d9428888-122b-11e1-b85c-61cd3cbb3216"
        db = Mock()
        db.select.side_effect = [
            [], [{"id": conversation_id}], [],
            [], [{"id": report_id}],
            [],
        ]
        worker = Worker(Settings("https://example.supabase.co", "test-only", "worker-id"), db=db)
        job = {"id": job_id, "lease_token": lease_token, "requested_by": actor}
        worker._append_message(conversation_id, project_id, job, "answer")
        created_report_id = worker._save_report(project_id, job, {"title": "Draft"}, "report")
        worker._save_citations(project_id, job, [{"kind": "chunk", "id": source_id, "text": "evidence"}], created_report_id)
        self.assertEqual(
            [call.args[1]["processing_lease_token"] for call in db.insert.call_args_list],
            [lease_token, lease_token, lease_token],
        )

    def test_backoff_is_exponential_and_bounded(self):
        self.assertEqual(retry_delay_seconds(1), 15)
        self.assertEqual(retry_delay_seconds(2), 30)
        self.assertEqual(retry_delay_seconds(100), 3600)
        self.assertEqual(retry_delay_seconds(0), 15)


if __name__ == "__main__":
    unittest.main()
