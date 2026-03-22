"""
Train an EfficientNet-Lite0 plant classifier on the curated dataset.

Expects data in ImageFolder format:
  data/plants/train/<species>/image.jpg
  data/plants/val/<species>/image.jpg

Outputs:
  tools/plant_classifier_best.pt

Usage:
  python tools/train_plant_classifier.py [--epochs 30] [--batch-size 32] [--lr 1e-3]

Requires: pip install torch torchvision timm pillow
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms


def build_model(num_classes):
    """Create an EfficientNet-Lite0 classifier with a custom head."""
    try:
        import timm
    except ImportError:
        print("Installing timm...")
        import os

        os.system(f"{sys.executable} -m pip install timm")
        import timm

    model = timm.create_model("efficientnet_lite0", pretrained=True)

    # Replace classifier head
    in_features = model.classifier.in_features
    model.classifier = nn.Linear(in_features, num_classes)

    return model


def get_transforms(is_train):
    """Training and validation transforms."""
    if is_train:
        return transforms.Compose(
            [
                transforms.RandomResizedCrop(224, scale=(0.8, 1.0)),
                transforms.RandomHorizontalFlip(),
                transforms.RandomRotation(15),
                transforms.ColorJitter(
                    brightness=0.2, contrast=0.2, saturation=0.1, hue=0.05
                ),
                transforms.RandomApply([transforms.GaussianBlur(3)], p=0.2),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225],
                ),
            ]
        )
    else:
        return transforms.Compose(
            [
                transforms.Resize(256),
                transforms.CenterCrop(224),
                transforms.ToTensor(),
                transforms.Normalize(
                    mean=[0.485, 0.456, 0.406],
                    std=[0.229, 0.224, 0.225],
                ),
            ]
        )


def mixup_data(x, y, alpha=0.2):
    """Apply MixUp augmentation: blend pairs of images and labels."""
    if alpha > 0:
        lam = np.random.beta(alpha, alpha)
    else:
        lam = 1.0

    batch_size = x.size(0)
    index = torch.randperm(batch_size, device=x.device)

    mixed_x = lam * x + (1 - lam) * x[index]
    y_a, y_b = y, y[index]
    return mixed_x, y_a, y_b, lam


def mixup_criterion(criterion, pred, y_a, y_b, lam):
    """Compute MixUp loss as weighted combination."""
    return lam * criterion(pred, y_a) + (1 - lam) * criterion(pred, y_b)


def train_one_epoch(
    model, loader, criterion, optimizer, device, use_mixup=True, mixup_alpha=0.2
):
    model.train()
    total_loss = 0
    correct = 0
    total = 0

    for images, labels in loader:
        images, labels = images.to(device), labels.to(device)

        if use_mixup:
            images, targets_a, targets_b, lam = mixup_data(images, labels, mixup_alpha)
            optimizer.zero_grad()
            outputs = model(images)
            loss = mixup_criterion(criterion, outputs, targets_a, targets_b, lam)
            loss.backward()
            optimizer.step()

            # Accuracy uses the dominant label
            _, predicted = outputs.max(1)
            correct += (
                lam * predicted.eq(targets_a).sum().item()
                + (1 - lam) * predicted.eq(targets_b).sum().item()
            )
        else:
            optimizer.zero_grad()
            outputs = model(images)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()

            _, predicted = outputs.max(1)
            correct += predicted.eq(labels).sum().item()

        total_loss += loss.item() * images.size(0)
        total += labels.size(0)

    return total_loss / total, correct / total


@torch.no_grad()
def validate(model, loader, criterion, device):
    model.eval()
    total_loss = 0
    correct = 0
    total = 0

    for images, labels in loader:
        images, labels = images.to(device), labels.to(device)
        outputs = model(images)
        loss = criterion(outputs, labels)

        total_loss += loss.item() * images.size(0)
        _, predicted = outputs.max(1)
        correct += predicted.eq(labels).sum().item()
        total += labels.size(0)

    return total_loss / total, correct / total


def main():
    parser = argparse.ArgumentParser(description="Train plant classifier")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument(
        "--label-smoothing",
        type=float,
        default=0.1,
        help="Label smoothing factor (default: 0.1)",
    )
    parser.add_argument(
        "--mixup-alpha",
        type=float,
        default=0.2,
        help="MixUp alpha parameter (default: 0.2, 0 to disable)",
    )
    args = parser.parse_args()

    data_dir = Path(__file__).parent.parent / "data" / "plants"
    train_dir = data_dir / "train"
    val_dir = data_dir / "val"
    out_path = Path(__file__).parent / "plant_classifier_best.pt"

    if not train_dir.exists():
        print(f"ERROR: {train_dir} not found. Run build_plant_dataset.py first.")
        sys.exit(1)

    # Device
    if torch.backends.mps.is_available():
        device = torch.device("mps")
    elif torch.cuda.is_available():
        device = torch.device("cuda")
    else:
        device = torch.device("cpu")
    print(f"Using device: {device}")

    # Datasets
    train_dataset = datasets.ImageFolder(str(train_dir), transform=get_transforms(True))
    val_dataset = datasets.ImageFolder(str(val_dir), transform=get_transforms(False))

    num_classes = len(train_dataset.classes)
    print(f"Classes: {num_classes}")
    print(f"Train images: {len(train_dataset)}")
    print(f"Val images: {len(val_dataset)}")

    train_loader = DataLoader(
        train_dataset,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=args.workers,
        pin_memory=True,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=args.batch_size,
        shuffle=False,
        num_workers=args.workers,
        pin_memory=True,
    )

    # Model
    model = build_model(num_classes).to(device)
    criterion = nn.CrossEntropyLoss(label_smoothing=args.label_smoothing)
    use_mixup = args.mixup_alpha > 0
    print(f"Label smoothing: {args.label_smoothing}")
    print(f"MixUp: {'alpha=' + str(args.mixup_alpha) if use_mixup else 'disabled'}")
    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=args.lr,
        weight_decay=args.weight_decay,
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(
        optimizer,
        T_max=args.epochs,
    )

    # Training loop
    best_val_acc = 0.0
    print(
        f"\n{'Epoch':>5} {'TrainLoss':>10} {'TrainAcc':>10} {'ValLoss':>10} {'ValAcc':>10} {'LR':>10}"
    )
    print("-" * 60)

    for epoch in range(1, args.epochs + 1):
        train_loss, train_acc = train_one_epoch(
            model,
            train_loader,
            criterion,
            optimizer,
            device,
            use_mixup=use_mixup,
            mixup_alpha=args.mixup_alpha,
        )
        val_loss, val_acc = validate(model, val_loader, criterion, device)
        lr = optimizer.param_groups[0]["lr"]
        scheduler.step()

        marker = ""
        if val_acc > best_val_acc:
            best_val_acc = val_acc
            torch.save(
                {
                    "epoch": epoch,
                    "model_state_dict": model.state_dict(),
                    "num_classes": num_classes,
                    "class_to_idx": train_dataset.class_to_idx,
                    "val_acc": val_acc,
                },
                out_path,
            )
            marker = " *"

        print(
            f"{epoch:5d} {train_loss:10.4f} {train_acc:10.4f} "
            f"{val_loss:10.4f} {val_acc:10.4f} {lr:10.6f}{marker}"
        )

    print(f"\nBest validation accuracy: {best_val_acc:.4f}")
    print(f"Model saved to: {out_path}")

    # Also save the class-to-idx mapping for reference
    idx_to_class = {v: k for k, v in train_dataset.class_to_idx.items()}
    class_map = {i: idx_to_class[i] for i in range(num_classes)}
    class_file = (
        Path(__file__).parent.parent / "assets" / "models" / "plant_classes.json"
    )
    with open(class_file, "w") as f:
        json.dump(class_map, f, indent=2)
    print(f"Class mapping saved to: {class_file}")


if __name__ == "__main__":
    main()
