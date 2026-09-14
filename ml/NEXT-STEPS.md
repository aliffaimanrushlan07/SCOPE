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

## 2. Augmentation is the weakest part of training

Current augmentation (notebook cell 8) is horizontal flip plus brightness,
contrast and saturation jitter. That is a light CNN-era recipe, and Vision
Transformers are known to need more on datasets of this size — 1,358 training
images is small for a ViT-Base.

It also does not rehearse the domain gap the README names honestly: real
submissions will be **further away, more motion-blurred and worse lit** than
web-sourced photographs. The augmentation should simulate exactly that.

Add, in rough order of value:

| Technique | Why here | Source |
|---|---|---|
| RandomResizedCrop (scale 0.6–1.0) | Rehearses subject distance — the main domain gap | standard ViT recipe |
| Motion blur, Gaussian blur, JPEG compression, downscale | Rehearses phone-camera conditions; also makes the "too blurry" band meaningful | [albumentations](https://github.com/albumentations-team/albumentations) |
| RandAugment | Standard ViT policy; replaces the hand-rolled jitter | [DeiT](https://github.com/facebookresearch/deit), arXiv:2012.12877 |
| Mixup + CutMix | The DeiT recipe's main defence against ViT overfitting on small data | same |
| Random Erasing | Occlusion robustness (hands, phones, crowds) | same |

`keras_cv.layers` provides `RandAugment`, `MixUp`, `CutMix` and
`RandomCutout` as Keras layers, so this stays inside the TensorFlow stack that
Table 3.5 commits to. No PyTorch needed.

Note: Mixup and CutMix produce soft labels, so the loss must move from
`SparseCategoricalCrossentropy` to `CategoricalCrossentropy` with one-hot
labels.

---

## 3. Training is not measuring the thing being optimised

`metrics=['accuracy']` and `EarlyStopping(monitor='val_loss')`. Neither is
precision. The retained checkpoint is therefore the one with the best loss,
not the one that would serve S10 best.

```python
metrics=[
    'accuracy',
    keras.metrics.Precision(name='precision'),
    keras.metrics.Recall(name='recall'),
    keras.metrics.AUC(name='pr_auc', curve='PR'),
]
...
keras.callbacks.EarlyStopping(monitor='val_pr_auc', mode='max',
                              patience=3, restore_best_weights=True)
```

PR-AUC rather than precision-at-0.5, because it is threshold-independent and
so does not fight the threshold selection in §1.

Add label smoothing at the same time — `label_smoothing=0.1`. The score
distribution (mean 0.939 for smoking, 0.055 for not) is very hard, which is
exactly the over-confidence label smoothing exists to temper.

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
2. Add precision/recall/PR-AUC metrics and PR-AUC early stopping. **(§3)**
3. Add the stronger augmentation pipeline and label smoothing. **(§2, §3)**
4. Retrain across 3 seeds; report mean ± SD. **(§4)**
5. Calibrate. **(§5)**
6. TTA and the ≥2-photo analysis. **(§6)**

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
