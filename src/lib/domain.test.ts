import { describe, expect, it } from "vitest";
import { isReviewableTask, taskStatusLabels } from "@/lib/domain";

describe("task review states", () => {
  it("distinguishes submitted work from terminal approvals", () => {
    expect(isReviewableTask("submitted")).toBe(true);
    expect(isReviewableTask("under_review")).toBe(true);
    expect(isReviewableTask("approved")).toBe(false);
  });

  it("has a user-facing label for every supported state", () => {
    expect(Object.keys(taskStatusLabels)).toEqual([
      "not_started", "in_progress", "submitted", "under_review", "approved", "changes_requested"
    ]);
  });
});
