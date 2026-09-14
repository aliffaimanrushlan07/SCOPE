# Raising classifier rigour — what is left to do

Supervisor feedback: *precision is not sufficient; add further training
techniques, sourced from reliable repositories.*

This file exists because the obvious reading of that feedback — "the precision
number is low" — is not what the evidence says. Test precision is **0.977** at
threshold 0.70. What is thin is the **method and the evidence behind that
number**, and one step of it is methodologically wrong. That is what this file
addresses.

---

## Already done — do not redo

| Technique | Where |
|---|---|
| Transfer learning from an ImageNet-21k checkpoint | `vit_base_patch16_224_imagenet21k` via KerasHub |
| Two-phase fine-tune (freeze head → unfreeze at 1e-5) | `notebooks/finetune_vit.ipynb` cells 10–14 |
| Leakage-free split by perceptual hash, stratified, seeded | `prepare_dataset.py`; asserted in notebook cell 6 |
| De-duplication (69 near-duplicates removed) | `prepare_dataset.py` |
| Threshold sweep with an explicit precision target | `select_threshold.py` |
| Cost-asymmetry reasoning for the operating point | `README.md` |
| Re-scoring through the backend's own inference path | `artifacts/test_scores_backend.csv` |

Any plan that proposes these is proposing work that is finished.

---

## 1. The threshold is tuned on the test set — TOOLING DONE, RUN OUTSTANDING

The chosen 0.70 came from `test_scores_backend.csv` — the **held-out test
split**. Selecting the operating point there and then reporting test metrics at
that point is **optimistically biased**: the threshold has been fitted to the
same 293 images the result is claimed on, so the reported 0.977 is an upper
bound on itself rather than an independent estimate.

This is the single most likely thing a supervisor means by "not rigorous
enough". The tooling for the correct procedure is now in place:

- `ml/score_split.py` — scores any split through `inference.score_images`, the
  backend's own entry point, into `artifacts/<split>_scores_backend.csv`.
- `select_threshold.py` now defaults to `val_scores_backend.csv`, and warns
  when asked to sweep a file whose name contains `test`.
- `select_threshold.py --at-threshold <value>` reports metrics at a frozen
  threshold and offers no choice, so the reporting step cannot quietly become
  a second selection step.

**What is left is the run itself**, after the next training run produces a
model:

```bash
./backend/.venv/bin/python ml/score_split.py val
./backend/.venv/bin/python ml/select_threshold.py ml/artifacts/val_scores_backend.csv
# freeze what it returns, then:
./backend/.venv/bin/python ml/score_split.py test
./backend/.venv/bin/python ml/select_threshold.py \
    ml/artifacts/test_scores_backend.csv --at-threshold <frozen>
```

Then update `AI_CONFIDENCE_THRESHOLD` in `backend/.env`, and the results table
and threshold sweep in `ml/README.md`.

Expect the test precision to come out slightly lower than 0.977. That is the
honest number, and reporting it with the method stated is worth more marks
than a higher number obtained the current way.

---

## 2. Augmentation is the weakest part of training — IMPLEMENTED, RUN OUTSTANDING

The old recipe was horizontal flip plus brightness/contrast/saturation jitter:
a light CNN-era pipeline for a ViT-Base on 1,358 images, and one that did not
rehearse the domain gap the README names — real submissions are **further
away, more motion-blurred and worse lit** than web-sourced photographs.

Notebook cell 8 now implements, in `tf.image`:

| Technique | Why here | State |
|---|---|---|
| RandomResizedCrop, scale 0.6–1.0 | Rehearses subject distance — the main domain gap | done |
| Random horizontal flip | Kept from the old recipe | done |
| RandAugment-style policy, N=2 ops | Replaces three hand-tuned constants with a sampled policy | done |
| Gaussian blur, motion blur, downscale, JPEG | Rehearses phone-camera conditions | done |
| Random erasing | Occlusion robustness (hands, phones, crowds) | done |
| Mixup + CutMix | The other half of the DeiT recipe | **not done — see below** |

Two deliberate departures from the plan as first written:

**Hand-rolled `tf.image`, not `keras_cv`.** keras-cv is in maintenance and its
co-install with Keras 3 and keras-hub is fragile on Colab; a broken import at
the top of a training run costs more than the citation is worth. The policy is
therefore *RandAugment-style* — N ops sampled at a shared magnitude — and not
the published op list, which the report should say. Cite arXiv:1909.13719 for
the method, not for this implementation.

**Mixup and CutMix are still outstanding.** They produce soft labels that
interact with the label smoothing added in §3, and their effect is worth
measuring on its own row of the results table rather than bundled in with
everything else here.

The crop takes its region from the image as stored (long side 256), not from a
pre-resized 224 copy, so it keeps detail a pre-resize would have discarded.

**What is left is the retrain**, and a row in the results table comparing
precision and recall before and after.

---

## 3. Training is not measuring the thing being optimised — IMPLEMENTED, RUN OUTSTANDING

`metrics=['accuracy']` and `EarlyStopping(monitor='val_loss')` meant the
retained checkpoint was the one with the best loss, not the one that serves S10
best. Cell 10 now compiles with precision, recall and PR-AUC, and both training
stages early-stop on `val_pr_auc` with `mode='max'`.

Two things that are easy to get wrong here, and are handled:

**The metrics read the positive-class column.** `keras.metrics.Precision` on a
2-column softmax compares the whole output against the whole target, averaging
the positive class with its own complement. On a worked example that reports
0.600 where the real positive-class precision is 0.667. The notebook therefore
wraps Precision, Recall and AUC to slice `[:, POSITIVE_INDEX]` first.

**`mode='max'` is not optional.** With the default `mode='auto'` on an
unrecognised metric name, Keras can minimise PR-AUC and restore the worst
weights of the run.

Label smoothing (`label_smoothing=0.1`) went in at the same time. It forced the
loss from `SparseCategoricalCrossentropy` to `CategoricalCrossentropy` and the
labels to one-hot, since Keras implements smoothing only on the latter — the
same change Mixup would have needed. Smoothing is applied inside the loss, so
the metrics still see clean 0/1 targets.

PR-AUC rather than precision-at-0.5, because it is threshold-independent and so
does not fight the threshold selection in §1.

---

## 4. One run is not a result

The README already concedes this: the test split was used once, so the
figures carry the variance of a single training run. A supervisor is entitled
to ask how much of 0.977 is the method and how much is the seed.

Retrain with **3 seeds** and report **mean ± standard deviation** for
precision, recall, F1 and PR-AUC. On a T4 this is a few hours of Colab, not a
redesign.

If the three runs disagree by more than a point or two, that spread is itself
a finding worth stating.

---

## 5. Calibration

Scores cluster at the extremes, which usually means the network is
over-confident — a raw 0.95 does not mean 95% likely to be correct. This
matters because the confidence is surfaced to the administrator on D05 as
decision support.

Fit a single temperature scalar on the validation split (Guo et al.,
arXiv:1706.04599) and apply it at inference. One parameter, ~20 lines, and it
makes `REPORT_PHOTO.confidence_score` mean what it appears to mean.

---

## 6. Cheap inference-time gains, if time allows

- **Test-time augmentation** — average the score over the image and its
  horizontal flip. One extra forward pass per photograph.
- **Hard negatives** — the corpus contains some confusable non-smoking
  gestures, but more (phone to ear, drinking, vaping, pen) would attack the
  remaining 3 false positives directly.
- **Report-level rule** — the README's §8 analysis of the ≥1-photo rule is
  good. Requiring **≥2 of 3** photographs to clear the threshold would cut the
  5.84% invalid-report rate further with no model change. Worth computing from
  `photos_evaluated` / `photos_passed` and reporting as an option, even if not
  adopted.

---

## Order of work

1. Re-tune the threshold on validation, re-report on test. **(§1 — tooling
   done, needs a run against a trained model)**
2. Add precision/recall/PR-AUC metrics and PR-AUC early stopping. **(§3 —
   implemented, needs a run)**
3. Add the stronger augmentation pipeline and label smoothing. **(§2, §3 —
   implemented, needs a run)**
4. Retrain across 3 seeds; report mean ± SD. **(§4)**
5. Calibrate. **(§5)**
6. TTA and the ≥2-photo analysis. **(§6)**

Everything from §1 to §3 is now implemented but unmeasured: the next Colab run
is what turns it into evidence. Export that model as **`vit-scope-v2`** and
bump `AI_MODEL_VERSION` — `vit-scope-v1`'s scores were produced by a different
recipe, and `AI_CLASSIFICATION.model_version` is what keeps them apart.

Keep a results table from step 1, one row per change, precision and recall
before and after. That table is the answer to "what techniques did you add" —
it turns a list of citations into evidence.

A lower number after step 1 is **correct**, not a regression. Say so in the
report.

---

## Sources

- [facebookresearch/deit](https://github.com/facebookresearch/deit) · [arXiv:2012.12877](https://arxiv.org/abs/2012.12877) — augmentation recipe for ViTs on small data
- [keras-team/keras-cv](https://github.com/keras-team/keras-cv) — RandAugment, MixUp, CutMix as Keras layers
- [albumentations](https://github.com/albumentations-team/albumentations) — blur, compression, downscale transforms
- [Guo et al., arXiv:1706.04599](https://arxiv.org/abs/1706.04599) — temperature scaling
- [Szegedy et al., arXiv:1512.00567](https://arxiv.org/abs/1512.00567) — label smoothing
- [scikit-learn — tuning the decision threshold](https://scikit-learn.org/stable/modules/classification_threshold.html)
- [Khan et al. (2023), SmokerViT, CMC 77(1)](https://www.techscience.com/cmc/v77n1/54461)
