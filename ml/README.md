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
| Model fine-tuned | ✅ `vit-scope-v1` |
| Threshold chosen | ⚠️ **0.70**, but selected on the test split — [re-select on validation](#5-threshold) |
| Wired into the backend | ✅ real inference, stub removed |

---

## Results

Fine-tuned `vit_base_patch16_224_imagenet21k` on 1,358 training images,
validated on 290, and evaluated **once** on 293 held-out test images.

| Metric at threshold 0.70 | Value |
|---|---|
| Precision | **0.977** |
| Recall | **0.916** |
| F1 | 0.945 |
| Accuracy | 0.949 |
| Confusion | TP 130 · FP 3 · FN 12 · TN 148 |

Mean score for smoking images **0.939**, for non-smoking **0.055** — a
separation of 0.884, meaning the model is decisive rather than hedging.

> **These figures are from `vit-scope-v1` and will change.** Two reasons.
>
> The 0.70 threshold was selected by sweeping these same test scores, so the
> operating point was fitted to the images the result is claimed on. The
> tooling for the correct procedure — select on validation, report on test — is
> in place (`score_split.py`, and `select_threshold.py --at-threshold`).
>
> The training recipe has also changed since this run: stronger augmentation,
> precision/recall/PR-AUC metrics, PR-AUC early stopping and label smoothing
> (step 4 below). `vit-scope-v1` predates all of it.
>
> The next run trains under the new recipe and re-measures under the correct
> procedure. **Export it as `vit-scope-v2`** and bump `AI_MODEL_VERSION`, so
> `AI_CLASSIFICATION.model_version` keeps historical confidence scores
> interpretable. Expect precision to fall slightly once the threshold is chosen
> on validation. That is the honest figure, not a regression.

### Threshold sweep

| Threshold | Precision | Recall | F1 | TP | FP | FN | TN |
|---|---|---|---|---|---|---|---|
| 0.10 | 0.892 | 0.993 | 0.940 | 141 | 17 | 1 | 134 |
| 0.20 | 0.928 | 0.993 | 0.959 | 141 | 11 | 1 | 140 |
| 0.30 | 0.945 | 0.965 | 0.955 | 137 | 8 | 5 | 143 |
| 0.33 | 0.951 | 0.965 | 0.958 | 137 | 7 | 5 | 144 |
| 0.50 | 0.964 | 0.951 | 0.957 | 135 | 5 | 7 | 146 |
| **0.70** | **0.977** | **0.916** | **0.945** | **130** | **3** | **12** | **148** |
| 0.80 | 0.977 | 0.901 | 0.938 | 128 | 3 | 14 | 148 |
| 0.90 | 0.976 | 0.873 | 0.922 | 124 | 3 | 18 | 148 |
| 0.95 | 0.992 | 0.866 | 0.925 | 123 | 1 | 19 | 150 |

---

## Why 0.70 and not the best-F1 point

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

**Domain gap.** Most training images are web-sourced photographs, not phone
photos taken at a distance in a Malaysian food court. Real submissions will be
further from the camera, more motion-blurred, and worse lit. v3 narrows the gap
with 174 phone photographs (131 hard negatives, 43 field-condition lit
cigarettes), and the augmentation rehearses distance and blur, but field photos
are still under 10% of the data and only 30 of them are in test. Measured
accuracy remains an **upper bound** on field performance: the phone tests in
this project found errors the test split had not.

**Failure reasons are partly heuristic.** Blur is measured: a photograph below
the sharpness cutoff fails as "Image too blurry" on a variance-of-Laplacian
measurement, not on its score. "Too far" and "no lit cigarette" are still
presentational bands over the confidence score, because a single-label
classifier reports how sure it is, not why. Distance from a detection bounding
box would make "too far" a measurement too.

**No human check.** FR12 was removed, so a false positive reaches enforcement
uncorrected. The defence is that the operating point is set to minimise
exactly that: at 0.90, vit-scope-v3 accepted 0 of 173 non-smoking test
photographs, including 0 of 22 hard negatives (95% CI on precision
0.967–1.000). The dashboard is also advisory: it informs patrol planning rather
than triggering enforcement against a named party.

**Single training run for v3.** vit-scope-v2 was retrained across 3 seeds
(precision 0.975 ± 0.008, `artifacts/seed_study.txt`); vit-scope-v3 has not
been, so its figures carry the variance of one run. Section 11 of the notebook
and `aggregate_seeds.py` measure that spread; until they are run for v3, quote
the confidence intervals `select_threshold.py` prints and say the seed
variance is unmeasured. The v3 test split has also been read twice — at 0.71
and at 0.90, both fixed beforehand — so it must not be used to tune again.

**The test split is small.** With 173 non-smoking images, the 95% confidence
interval on precision is still a few points wide (0.967–1.000 at 0.90), and
only 22 of those images are hard negatives — too few to measure any single
object, such as straws, on its own. Averaging over training seeds does not
narrow that; only more labelled test data would. Both sources of uncertainty
should be stated; neither alone answers "how much of this is luck".

**A photograph of a screen showing a lit cigarette is accepted.** The model
judges what the picture shows, not whether it is a real scene: a phone photo of
a laptop playing a cigarette stock video scored 0.932 and passed both the 0.90
threshold and the sharpness check (screens photograph sharply). No photographs
of screens are in the training negatives. This is **accepted deliberately**:
the live demonstration is held indoors, where lighting a real cigarette would
be unsafe and unhealthy, so the demo photographs a lit cigarette on a screen.
Misuse to fabricate a report is bounded by camera-only capture at S08 and the
per-device limit of 5 reports per hour. The fix, if needed, is a v4 dataset
with photographs of screens labelled as non-smoking; a hand-written moiré
detector was considered and rejected as too sensitive to angle and distance.

**An unlit cigarette is not a training negative.** The model learned "smoking"
from photographs that are mostly lit, but was never shown an unlit cigarette
held the same way, so it may accept one. Like screens, this needs v4 data.

**The 0.90 threshold is a policy, not a rule output.** The validation-first
procedure gives 0.71 for vit-scope-v3. 0.90 was set above it deliberately for
strictness and fixed before test was scored at it; its cost (recall 0.747) is
stated alongside its benefit (0 of 22 hard negatives accepted).

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

### v3 — hard negatives (dataset of 2,119 images)

174 new phone photographs were added: 131 hard negatives (pens, pencils,
chopsticks, lipstick, straws, an empty hand at the mouth) and 43 lit
cigarettes in field conditions. `prepare_dataset.py` kept every v2 image in
its existing split and assigned only the new ones, so both models below are
scored on the same held-out test split (323 images, 22 of them hard
negatives), which neither model trained on.

| Model | Threshold (chosen on validation) | Precision | Recall | PR-AUC | FP | FN | Hard negatives accepted |
|---|---|---|---|---|---|---|---|
| vit-scope-v2 | 0.66 | 0.872 | 0.907 | 0.962 | 20 | 14 | 18 / 22 |
| **vit-scope-v3** | **0.71** (target precision 1.00) | **0.978** | **0.880** | **0.989** | **3** | **18** | **1 / 22** |

"At a threshold of 0.71, selected on the validation split, vit-scope-v3
reached precision 0.978 and recall 0.880 on the held-out test split (323
images), with a 95% confidence interval on precision of [0.937, 0.992],
accepting 1 of 22 hard-negative photographs against 18 for vit-scope-v2."

On this split v2's precision is 0.872, well below the 0.985 it reached on the
v2 test split: that split contained no look-alike objects, so it could not
reveal the weakness a phone test found. The one hard negative v3 still accepts
is a pen from that phone test (0.967 under v2, 0.825 under v3). All 8
field-condition cigarette photographs in test pass under both models. Single
training run; seed variance for v3 is not yet measured.

### Strict operating point — threshold 0.90 and a sharpness check

After a fresh pen photograph (0.827) still passed under v3 at 0.71, the
operating point was raised to **0.90** as a deliberate policy: only clear
photographs of a lit cigarette should be accepted, and a retake is an accepted
cost. This is **not** the output of the validation rule, which gives 0.71 and
sees no false positives to remove above it. 0.90 was fixed before test was
read at it, and should be described in the report as a policy choice.

A measured blur check was added at the same time (`AI_MIN_SHARPNESS`,
`inference.sharpness`): variance of the Laplacian at a 512 px long side. A
photograph below the cutoff fails as "Image too blurry" whatever it scores,
and a sharp photograph is no longer blamed on blur. The cutoff of **20** was
calibrated on validation: it rejects 0 of 148 genuine smoking photographs and
catches 97% of copies blurred with a Gaussian of radius 2 (100% at radius 4).

| vit-scope-v3, test split (323 images) | 0.71 | **0.90 + sharpness 20** |
|---|---|---|
| Precision | 0.978 | **1.000** (95% CI 0.967–1.000) |
| Recall | 0.880 | **0.747** (95% CI 0.672–0.810) |
| FP / FN | 3 / 18 | **0 / 38** |
| Hard negatives accepted | 1 / 22 | **0 / 22** |
| Field lit-cigarette photos accepted | 8 / 8 | 6 / 8 |
| Genuine photos rejected for blur alone | — | 0 |

At the report level (up to three photographs, one needed), 0% of invalid
reports reach enforcement and 1.6% of genuine three-photo reports are
rejected, but a single-photograph genuine report is rejected about 1 time in
4. The sharpness check catches blur only; it does not detect a photograph of a
screen, and an unlit cigarette is not a training negative — both remain
limitations until a v4 dataset includes them.
