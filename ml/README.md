# SCOPE — AI classification module

The evidence classifier used at **S10**. Given a photograph, it returns
P(smoking violation); the backend compares that against a configurable
threshold and accepts the report when at least one photograph clears it.

---

## Status — complete

| Step | State |
|---|---|
| Tooling (`prepare_dataset.py`, `select_threshold.py`, notebook) | ✅ |
| Dataset assembled and split | ✅ 1,941 images |
| Model fine-tuned | ✅ `vit-scope-v2` (DeiT-style augmentation, PR-AUC early stopping, label smoothing) |
| Threshold chosen | ✅ **0.66**, selected on validation, reported once on test — [procedure](#5-threshold) |
| Wired into the backend | ✅ real inference, stub removed |

---

## Results

Fine-tuned `vit_base_patch16_224_imagenet21k` on 1,358 training images. The
threshold was selected on the 290 validation images and then frozen; the
figures below are the 293 held-out test images scored at that frozen value,
through the backend's own inference path.

| Metric at threshold 0.66 (test) | Value |
|---|---|
| Precision | **0.985** (95% CI 0.946–0.996) |
| Recall | **0.901** (95% CI 0.841–0.940) |
| F1 | 0.941 |
| Accuracy | 0.945 |
| PR-AUC | 0.992 |
| Confusion | TP 128 · FP 2 · FN 14 · TN 149 |

> "At a threshold of 0.66, selected on the validation split, the classifier
> reached precision 0.985 and recall 0.901 on the held-out test split (293
> images), with a 95% confidence interval on precision of [0.946, 0.996]."

Mean test score for smoking images **0.890**, for non-smoking **0.112**.

At the report level (up to three photographs, one needed to pass), 3.92% of
invalid reports would reach enforcement and 0.096% of genuine reports would be
wrongly rejected. Requiring 2 of 3 instead would give 0.05% and 2.724%.

This is a single training run. Across 3 seeds, each with its own
validation-selected threshold, test precision was 0.975 ± 0.008 and recall
0.897 ± 0.011 (`artifacts/seed_study.txt`). With 151 non-smoking test images,
the sampling half-width on precision (~0.03) is larger than the seed spread.

### Threshold sweep — validation (where the threshold is chosen)

| Threshold | Precision | Recall | F1 | TP | FP | FN | TN |
|---|---|---|---|---|---|---|---|
| 0.30 | 0.916 | 1.000 | 0.956 | 141 | 13 | 0 | 136 |
| 0.40 | 0.952 | 0.993 | 0.972 | 140 | 7 | 1 | 142 |
| 0.50 | 0.972 | 0.979 | 0.975 | 138 | 4 | 3 | 145 |
| 0.60 | 0.985 | 0.950 | 0.968 | 134 | 2 | 7 | 147 |
| 0.63 | 0.992 | 0.929 | 0.960 | 131 | 1 | 10 | 148 |
| **0.66** | **1.000** | **0.929** | **0.963** | **131** | **0** | **10** | **149** |
| 0.70 | 1.000 | 0.908 | 0.952 | 128 | 0 | 13 | 149 |
| 0.80 | 1.000 | 0.879 | 0.936 | 124 | 0 | 17 | 149 |
| 0.90 | 1.000 | 0.752 | 0.858 | 106 | 0 | 35 | 149 |

0.66 is the lowest threshold with zero false positives on validation, so it
costs no recall over 0.63. Going higher only rejects more genuine photographs.
Do not re-pick it from the test numbers above; the test split has already been
read at 0.63 and 0.66.

### Earlier: `vit-scope-v1`

`vit-scope-v1` reached precision 0.977 and recall 0.916 at threshold 0.70
(TP 130 · FP 3 · FN 12 · TN 148). That threshold was selected by sweeping the
test scores, so the figure is optimistically biased and is kept only for
history. The next section explains the reasoning behind that choice; the
report-level arithmetic applies unchanged to v2.

---

## Why 0.70 and not the best-F1 point (`vit-scope-v1`)

`select_threshold.py` recommends **0.33** — the highest recall that still
holds precision at 0.95, and close to the best-F1 point. **0.70 was chosen
instead**, and the reasoning matters more than the number.

### The ≥1-photo rule changes the arithmetic

A report passes when **any one** of up to three photographs clears the
threshold (§8). So a false positive gets **three independent chances** per
report, while a false negative requires **all three** photographs to fail.
Per-photo metrics do not show this.

| Threshold | Per-photo FPR | Per-photo FNR | **Invalid report accepted** | **Genuine 3-photo report rejected** |
|---|---|---|---|---|
| 0.33 | 4.64% | 3.52% | **13.27%** | 0.004% |
| 0.50 | 3.31% | 4.93% | 9.61% | 0.012% |
| **0.70** | **1.99%** | **8.45%** | **5.84%** | **0.060%** |
| 0.90 | 1.99% | 12.68% | 5.84% | 0.204% |
| 0.95 | 0.66% | 13.38% | 1.97% | 0.240% |

Moving from 0.33 to 0.70 **more than halves** the rate at which an invalid
report reaches enforcement, while the chance of wrongly rejecting a genuine
three-photograph report stays below one in a thousand.

### Why not higher

0.95 looks better still — until you notice its 0.66% false-positive rate rests
on **exactly one** misclassified image out of 151. A rate estimated from a
single sample is not a measurement. 0.70 sits on a **plateau**: the
false-positive rate is 1.99% at 0.70, 0.80 and 0.90 alike, so small errors in
the estimate do not move the operating point. It is a shelf, not a cliff edge.

0.95 would also reject 13.4% of genuine single-photograph reports, and many
reporters will take only one photograph.

### The asymmetry this reflects

§S10 requires the operating point to keep **false positives** low. The two
errors do not cost the same:

- A **false positive** forwards an invalid report to enforcement. Administrators
  are read-only and the AI decision is final, so nothing downstream catches it.
- A **false negative** asks the reporter to retake a photograph. Recoverable,
  and they are standing there.

---

## Reproducing this

### 1. Data

[Kaggle / Mendeley smoking-vs-not-smoking corpus](https://data.mendeley.com/datasets/7b52hhzs3r/1)
— **CC BY 4.0**, attribution required. Cite it in Chapter 5.

Downloaded as `training_data/` + `validation_data/` + an unlabelled
`testing_data/`. The unlabelled folder is unusable and was discarded; the two
labelled folders were **merged and re-split from scratch** rather than reusing
the publisher's split, because that split was not verified leakage-free — and
in fact 69 duplicate images were found spanning it.

```
ml/data/raw/smoking/       1,005 images
ml/data/raw/notsmoking/    1,005 images
```

### 2. Split

```bash
./backend/.venv/bin/python ml/prepare_dataset.py
```

| Split | smoking | notsmoking | Total |
|---|---|---|---|
| train | 660 | 698 | 1,358 |
| val | 141 | 149 | 290 |
| test | 142 | 151 | 293 |
| **Total** | **943** | **998** | **1,941** |

69 duplicates removed by perceptual hash. Whole hash groups are assigned to a
single split, so near-identical frames cannot straddle train and test. Seeded
and reproducible; splitting happens before augmentation.

### 3. Bundle for Colab

```bash
./backend/.venv/bin/python ml/make_colab_bundle.py
```

453 MB → 23 MB by resizing to 256 px, which the model would do anyway.

### 4. Train

`ml/notebooks/finetune_vit.ipynb` in Google Colab, Runtime → **T4 GPU**.

Two stages: freeze the backbone and train the head, then unfreeze and
fine-tune at a lower learning rate.

**Augmentation** (training split only, `tf.image`, no extra dependency):
RandomResizedCrop at scale 0.6–1.0, horizontal flip, a RandAugment-style
policy of two sampled colour operations, then at most one phone-camera
degradation (Gaussian blur, motion blur, downscale, or JPEG re-encoding at
quality 30–75), then random erasing. A ViT-Base overfits 1,358 images through a
light recipe — this is the DeiT argument (arXiv:2012.12877) — and the crop and
degradations rehearse the domain gap named under *Limitations* below. Mixup and
CutMix are not included; they are worth measuring separately.

**What training measures.** Precision, recall and PR-AUC on the positive class,
with both stages early-stopping on `val_pr_auc` (`mode='max'`). Accuracy and
`val_loss` kept whichever checkpoint had the lowest loss, which on a
precision-critical task is not the one worth keeping. PR-AUC is
threshold-independent, so it does not fight the threshold selection in step 5.

Labels are **one-hot** and the loss is `CategoricalCrossentropy(label_smoothing=0.1)`:
Keras implements smoothing only there, and the current score distribution
(0.939 against 0.055) is exactly the over-confidence it tempers. Smoothing is
applied inside the loss, so the reported metrics still see clean 0/1 targets.

> **`activation='softmax'` is required and is not the default.** KerasHub ships
> `activation=None`, which returns raw logits. Pairing that with
> `from_logits=False` silently trains against a broken objective — the first
> run here did exactly that and produced negative "confidence" scores no
> threshold could act on. The notebook now asserts the output range immediately
> after building the model, before a training run is spent.

Uses **KerasHub**, not HuggingFace `transformers`, which has removed
TensorFlow support entirely — `TFViTForImageClassification` no longer exists.
KerasHub is Keras-native on the TensorFlow backend, so Table 3.5 stays accurate
and no PyTorch is involved.

### 5. Threshold

Two steps, in this order. They are not interchangeable.

```bash
# SELECT on validation — this is where the operating point is chosen
./backend/.venv/bin/python ml/score_split.py val
./backend/.venv/bin/python ml/select_threshold.py ml/artifacts/val_scores_backend.csv

# REPORT on test at the threshold that came back, changing nothing
./backend/.venv/bin/python ml/score_split.py test
./backend/.venv/bin/python ml/select_threshold.py \
    ml/artifacts/test_scores_backend.csv --at-threshold <frozen>
```

The threshold is a parameter fitted to data, like a weight. Fitting it on the
test split and then reporting test metrics at that point measures the model on
images the operating point was chosen to suit — the precision that comes back
is an upper bound on itself rather than an independent estimate. Sweeping a
file whose name contains `test` now prints a warning for exactly this reason.

If the threshold is adjusted after seeing the test figures, the test split has
been spent and the number is no longer independent. Change the model instead,
or state plainly in Chapter 5 that the split was reused.

Scores are recomputed **through the backend's own inference code** — the
`score_images` entry point that serves S10 — not taken from the notebook.
Resizing with PIL instead of TensorFlow shifted individual scores by up to
**0.46**, which would have silently invalidated the calibration.

### 6. Backend

```
AI_MODEL_PATH=../ml/artifacts/vit-scope-v1.keras
AI_MODEL_VERSION=vit-scope-v1
AI_CONFIDENCE_THRESHOLD=0.70
AI_STUB_MODE=false
```

The model loads once at application startup. The threshold is read per request,
so it can be retuned without rebuilding the mobile app — which is what §S10
requires.

---

## Limitations to state honestly in the report

**Domain gap.** The training images are web-sourced photographs, not phone
photos taken at a distance in a Malaysian food court. Real submissions will be
further from the camera, more motion-blurred, and worse lit. Measured accuracy
on this test set is an **upper bound** on field performance.

**Failure reasons are heuristic.** The model is a single-label classifier: it
reports how confident it is that a violation is present, not *why* it is
unconvinced. The "too blurry" / "too far" messages are presentational bands
over the confidence score, not measurements. Deriving blur from a Laplacian
variance check and distance from a detection bounding box would make them real.

**No human check.** FR12 was removed, so a false positive reaches enforcement
uncorrected. The defence is that the threshold is tuned to minimise exactly
that (3 false positives in 151 non-violations), and the dashboard is advisory —
it informs patrol planning rather than triggering enforcement against a named
party.

**Single evaluation run.** The test split was used once. Figures are not
averaged over repeated runs with different seeds, so they carry the variance of
a single training run. Section 11 of the notebook and `aggregate_seeds.py`
measure that spread; until they have been run, quote the confidence intervals
`select_threshold.py` prints and say the seed variance is unmeasured.

**The test split is small.** With 151 non-smoking images, the 95% confidence
interval on precision is roughly ±0.03. Averaging over training seeds does not
narrow that — only more labelled test data would. Both sources of uncertainty
should be stated; neither alone answers "how much of this is luck".

**The published threshold was selected on the test split.** Until the model is
retrained and the validation-first procedure in section 5 is run end to end,
the reported precision of 0.977 is an upper bound on itself. The procedure is
implemented; the figures are not yet re-measured under it.

---

## Files

| Path | Purpose |
|---|---|
| `prepare_dataset.py` | De-duplicate, split, manifest |
| `make_colab_bundle.py` | Resize + zip for upload |
| `score_split.py` | Score a split through the backend's inference code |
| `aggregate_seeds.py` | mean ± SD across training seeds |
| `select_threshold.py` | Threshold selection (val) and reporting (test) |
| `notebooks/finetune_vit.ipynb` | Training |
| `data/manifest.csv` | The authoritative split (gitignored) |
| `data/report.md` | Composition table for Chapter 5 |
| `artifacts/vit-scope-v1.keras` | Trained model, ~982 MB (gitignored) |
| `artifacts/val_scores_backend.csv` | Scores the threshold is SELECTED on |
| `artifacts/test_scores_backend.csv` | Scores the threshold is REPORTED on |


| Model | Threshold chosen on | Precision | Recall | PR-AUC |
|---|---|---|---|---|
| vit-scope-v1 | test (biased) | 0.977 | 0.916 | not measured |
| vit-scope-v2 | validation | 0.939 | 0.979 | 0.959 |
| vit-scope-v2 | validation, 0.63 (target precision 0.99) | 0.970 | 0.923 | 0.992 |
| vit-scope-v2 | validation, **0.66** (target precision 1.00) | **0.985** | **0.901** | 0.992 |

The move from 0.63 to 0.66 followed a phone test in which a non-cigarette
photograph was accepted. The new value was selected on validation by raising
the precision target to 1.00 — it is the lowest threshold with zero false
positives there (FP 1 → 0, recall unchanged at 0.929) — then reported once on
test: FP 4 → 2, FN 11 → 14, invalid 3-photo reports reaching enforcement
7.74% → 3.92%. 95% CI on test precision [0.946, 0.996]. Model unchanged, so
`AI_MODEL_VERSION` stays `vit-scope-v2`; `threshold_used` records the change
per classification. The test split has now been read at two thresholds; do
not tune against it again.
