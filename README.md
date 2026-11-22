# ripe-atlas-probe-docker

[RIPE Atlas Software Probe](https://github.com/RIPE-NCC/ripe-atlas-software-probe) を Docker コンテナとして動かすためのイメージです。
Ubuntu など、公式パッケージが提供されていないディストリビューションでも Docker さえあれば動かせます。

- 公式リポジトリのリリースタグから **公式の Debian パッケージをビルド** して Debian slim イメージにインストール
- `linux/amd64` / `linux/arm64` のマルチアーキテクチャ（Raspberry Pi 4/5 もOK）
- GitHub Actions が **毎週** upstream の最新リリースをチェックし、新バージョンがあれば自動ビルドして GHCR に push
- 新バージョンが出たら **Discord に通知**

## 使い方

```sh
mkdir ripe-atlas && cd ripe-atlas
curl -fsSLO https://raw.githubusercontent.com/fumons/ripe-atlas-probe-docker/main/docker-compose.yml
docker compose up -d
docker compose logs probe
```

設定変更は `docker-compose.yml` を直接編集するか、`docker-compose.override.yml` を置いて上書きしてください。

初回起動時にプローブ鍵が `./data/etc/probe_key` に生成され、ログに公開鍵と登録用URLが表示されます。

```
Probe public key (/etc/ripe-atlas/probe_key.pub):
    ssh-ed25519 AAAA... my-host

If this probe is not registered yet, register it at:
    https://atlas.ripe.net/register/swprobe?key=...
```

1. 表示された URL（または https://atlas.ripe.net/register/swprobe ）から公開鍵を登録
2. 登録が反映されると、プローブが定期的なリトライでコントローラに接続します（数分〜数十分かかることがあります）

> [!IMPORTANT]
> `./data/etc` には **プローブの秘密鍵** が入っています。必ずバックアップしてください。
> 鍵をなくすと別のプローブとして登録し直すことになります。

### 設定

`docker-compose.yml` の `environment` で以下を設定すると `/etc/ripe-atlas/config.txt` に書き込まれます（未指定の項目は変更しません）。

| 変数 | 説明 | 既定値 |
| --- | --- | --- |
| `RXTXRPT` | `yes` で送受信バイト数をレポート | なし |
| `TELNETD_PORT` | ローカルのステータス用 telnet ポート | `2023` |
| `HTTP_POST_PORT` | ローカルの HTTP POST ポート | `8080` |
| `PROBE_KEY_COMMENT` | 新規生成する鍵のコメント | ホスト名 |

### ネットワーク

`network_mode: host` を推奨します。ブリッジネットワークだと NAT 越しになり、IPv6 も使えないことが多いため、計測結果として意味が薄くなります。

### 注意点

- `security_opt: no-new-privileges` は付けないでください。計測用バイナリは setuid と `cap_net_raw` の file capability を使っています。
- `--cap-drop ALL` する場合は `docker-compose.yml` にある capability（特に `NET_RAW`, `SETUID`, `SETGID`）を残してください。
- 既存のホストインストールから移行する場合は、ホストの `/etc/ripe-atlas/probe_key{,.pub}` を `./data/etc/` にコピーすれば同じプローブとして動きます（元のホスト側のサービスは止めてください）。

### デバッグ

```sh
docker compose exec probe bash
docker run --rm -it ghcr.io/fumons/ripe-atlas-probe-docker:latest bash   # プローブを起動せずにシェル
```

## イメージタグ

| タグ | 内容 |
| --- | --- |
| `latest` | 最新の upstream リリース |
| `5130` など | upstream のバージョン番号（= GitHub リリースタグ） |

## GitHub Actions（`.github/workflows/build.yml`）

| トリガー | 動作 |
| --- | --- |
| 毎週月曜 03:00 UTC | upstream の最新リリース（pre-release 除く）を確認し、GHCR にそのタグがなければビルド＆push＋Discord通知 |
| `main` への push（Dockerfile 等の変更） | 現在の最新バージョンを再ビルド（通知なし） |
| 手動実行 (workflow_dispatch) | バージョン指定や強制再ビルドが可能 |

ビルドは amd64 / arm64 をそれぞれネイティブランナー（`ubuntu-24.04` / `ubuntu-24.04-arm`）で行い、最後にマルチアーキのマニフェストにまとめます。

### セットアップ

1. このリポジトリを GitHub に push
2. **Settings → Secrets and variables → Actions** で `DISCORD_WEBHOOK_URL` を追加
   （Discord のチャンネル設定 → 連携サービス → ウェブフック で URL を作成）。未設定なら通知はスキップされます。
3. **Actions** タブから `Build & publish image` を手動実行して初回ビルド
4. 初回 push 後、GHCR のパッケージは非公開になっているので、必要なら
   **Packages → ripe-atlas-probe-docker → Package settings** で Public に変更

> [!NOTE]
> `ubuntu-24.04-arm` ランナーはパブリックリポジトリなら無料で使えます。
> プライベートリポジトリで使えない場合は、arm64 の matrix を `ubuntu-24.04` ＋ QEMU（`docker/setup-qemu-action`）に置き換えてください（ビルドはかなり遅くなります）。

Discord 通知が届くのは次のときです。

- 新しいバージョンのイメージを公開したとき（緑）
- ビルドに失敗したとき（赤）

## ローカルビルド

```sh
docker build --build-arg ATLAS_VERSION=5130 -t ripe-atlas-probe .
```

## ライセンス

RIPE Atlas Software Probe 本体は RIPE NCC によるもので、GPL-3.0 で配布されています。
このリポジトリは非公式のパッケージングです。
