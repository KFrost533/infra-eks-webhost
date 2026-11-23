# EKS ウェブサイトホスティング

[English](README.md)

インフラストラクチャはローカルの Terraform モジュールとして構成されています。

| モジュール | 責務 |
|---|---|
| `eks` | EKS クラスター、Fargate プロファイル、アドオン、および任意の Fargate 制御機能 |
| `common` | ネットワーク、IAM、ロググループ、ECR、CodeBuild、GitHub 接続、アラート |

`terraform\stacks\main` と `terraform\stacks\eks` は別々の Terraform State を使用します。
モジュールディレクトリは機能単位で分けられており、リソースのライフサイクルを表すものではありません。

| 対象 | 所有スタック | 削除時の挙動 |
|---|---|---|
| 共有 VPC、ネットワーク、CodeBuild | `main` | `main` スタックが保持 |
| NAT Gateway、デフォルトルート | `eks` | EKS スタック削除時にプライベート送信経路も削除 |
| Fargate 制御 CloudWatch ログ | `main` | EKS 削除後もログを保持 |
| Fargate 制御アラーム | `eks` | EKS スタックと同時に削除 |

既存のロググループは Terraform の `moved` ブロックによって新しいモジュールアドレスへ
対応付けられます。適用前に必ず plan を確認してください。

| 設定種別 | 定義場所 | 上書き方法 |
|---|---|---|
| リージョン、プロジェクト名、クラスター名 | `main` スタック | `terraform\stacks\main\terraform.tfvars` |
| クラスターバージョン、VPC CIDR、スケジュール等 | 各モジュールの `variables.tf` | `terraform\stacks\eks\terraform.tfvars` |
| EKS から参照する共有設定 | `main` の `eks_shared` 出力 | `main` のローカル State ファイル |

既存環境へネットワークと CodeBuild の所有権変更を適用する前に、
各スタックを plan する前段階で State を移動してください。

```powershell
terraform -chdir=terraform\stacks\main state mv -state=..\eks\terraform.tfstate -state-out=terraform.tfstate module.network module.network
terraform -chdir=terraform\stacks\main state mv -state=..\eks\terraform.tfstate -state-out=terraform.tfstate module.codebuild module.codebuild
terraform -chdir=terraform\stacks\main state mv -state=terraform.tfstate -state-out=..\eks\terraform.tfstate module.network.aws_eip.nat module.network.aws_eip.this
terraform -chdir=terraform\stacks\main state mv -state=terraform.tfstate -state-out=..\eks\terraform.tfstate module.network.aws_nat_gateway.this module.network.aws_nat_gateway.this
```

プライベートルートテーブルのデフォルトルートは、インラインルートから EKS スタックが
所有する独立したリソースへ変更されます。どちらのスタックにも適用する前に、生成された
plan でこのルートの変更内容を確認してください。

想定するリリースフローは次のとおりです。

```text
GitHub push → CodeBuild → private ECR → Helm → EKS Fargate Pods
```

この設計は Fargate を使用し、EC2 ワーカーノードは作成しません。

## ネットワークと外部通信

| 項目 | 構成 | 注意点 |
|---|---|---|
| サブネット | パブリック／プライベート各2 AZ | パブリック側はインターネット公開 ALB 用 |
| 外部通信 | 第1パブリックサブネットの単一 NAT Gateway | NAT AZ 障害時は両方のプライベートサブネットが外部接続不可 |
| ECR 通信 | API/Docker インターフェイスエンドポイント＋S3 ゲートウェイエンドポイント | CodeBuild と Fargate は NAT なしで push/pull |
| AWS API | CloudWatch Logs、STS、EC2、ELB のインターフェイスエンドポイント | プライベートアクセスを使用 |
| MongoDB | Fargate から NAT の固定パブリック IP 経由 | 通常は TCP 27017 と DNS を許可 |
| ブラウザー通信 | ブラウザーから直接外部サービスへ接続 | VPC を経由しない |
| CodeBuild の公開通信 | NAT 経由の TCP 443 | Node.js イメージと npm 依存関係を取得するため、任意の公開 HTTPS 宛先へ接続可能 |
| EKS API | デフォルトはプライベートのみ | `cluster_admin_cidrs` 設定時だけパブリック API を有効化 |

パブリックネットワークの基盤は準備されていますが、AWS Load Balancer Controller と
パブリック ALB はまだインストールされていません。Helm チャートの Ingress はデフォルトで無効です。

## インフラストラクチャのプロビジョニング

| 前提条件 | 要件 |
|---|---|
| Terraform | 1.5.7 以上 |
| AWS | AWS CLI 認証情報 |
| コンテナ | Docker |
| IAM 権限 | VPC、EKS、IAM、ECR、CodeBuild、CodeConnections、CloudWatch の作成権限 |

**既存デプロイの場合:** 下記のとおり State 移行を完了するまで、どちらのルートも
適用しないでください。移行せずに実行すると、Terraform がリソースの削除や重複作成を
計画する可能性があります。

新規デプロイの場合は、リポジトリルートで次を実行します。

```powershell
Copy-Item terraform\stacks\main\terraform.tfvars.example terraform\stacks\main\terraform.tfvars
Copy-Item terraform\stacks\eks\terraform.tfvars.example terraform\stacks\eks\terraform.tfvars
```

`terraform\stacks\eks\terraform.tfvars` の `YOUR_PUBLIC_IP/32` を、作業者のパブリック
IPv4 CIDR に置き換えてください。

| リソース | `main` スタック | `eks` スタック |
|---|:---:|:---:|
| ECR、GitHub 接続、共有 IAM、CodeBuild ポリシー、ロググループ | 作成 | — |
| Fargate 制御用 IAM、SNS | 有効時のみ作成 | — |
| EKS、VPC、NAT、CodeBuild プロジェクト | 作成しない | 作成 |

CodeBuild モジュールは、EKS スタックの AWS リージョンにある既存の SSM Parameter Store
`String` パラメーター `/eks/video-platform-app` からリポジトリ URL を読み取ります。
この値には GitHub の HTTPS リポジトリ URL を設定する必要があり、Terraform の実行者には
値を読み取る権限が必要です。パラメーター変更後は EKS の plan を確認して適用し、
プロジェクトを更新してください。別の `website_repository_url` 入力は、Fargate 制御用
GitHub Actions ロールが信頼するリポジトリを指定します。CodeBuild のソースを変更しても、
この信頼関係は変更されません。

共有スタックは、同じ AWS アカウントにある既存の GitHub Actions IAM OIDC プロバイダーを
検索します。plan の前に別途このプロバイダーを作成または管理してください。このスタックでは
作成・変更・削除されません。過去の State ですでに
`module.iam.aws_iam_openid_connect_provider.github` を管理している場合は、設定適用前に
削除せず所有権を移し、plan を確認してください。

まず共有ルートの plan を確認して適用します。

```powershell
terraform -chdir=terraform\stacks\main init
terraform -chdir=terraform\stacks\main validate
terraform -chdir=terraform\stacks\main plan
terraform -chdir=terraform\stacks\main apply
```

ワークロードをデプロイする前に、AWS で GitHub 接続を承認してください。
EKS ルートは `terraform\stacks\main\terraform.tfstate` から `eks_shared` を自動的に読み取ります。

```powershell
terraform -chdir=terraform\stacks\eks init
terraform -chdir=terraform\stacks\eks validate
terraform -chdir=terraform\stacks\eks plan
terraform -chdir=terraform\stacks\eks apply
```

EKS スタックを plan、apply、destroy する前に main スタックを適用し、
main のローカル State ファイルを利用可能な状態に保ってください。このファイルへのアクセスは
main State 全体へのアクセス権に相当するため、適切に保護してください。
リモートバックエンドや別の State パスを使用する場合は、EKS のデータソースも対応するよう変更
してください。両方のルートは同じ AWS アカウントとリージョンを使用する必要があります。
EKS プロバイダーは共有出力に対してアカウントを検証します。

EKS スタックが存在する間は共有リソースを維持してください。共有 IAM、ECR、接続を
先に削除しないでください。共有 IAM、ログストレージ、ECR イメージなど、残存するリソースには
引き続き料金が発生する可能性があります。共有ルートで `enable_fargate_control` を無効化すると、
Lambda のロググループとそのログが削除されます。適用前に、実行中の EKS スタックへの影響を
確認してください。

### EKS の削除と再作成

EKS のコントロールプレーンや NAT Gateway には一時停止機能はありません。

| 操作 | コマンドまたは影響 |
|---|---|
| 削除 plan 確認 | `terraform -chdir=terraform\stacks\eks plan -destroy` |
| EKS スタック削除 | `terraform -chdir=terraform\stacks\eks destroy` |
| 削除されるもの | クラスター、VPC、NAT、エンドポイント、CodeBuild、Lambda、EventBridge、CloudWatch アラーム |
| 保持されるもの | 共有 IAM、SNS トピック、メール購読 |

必要に応じて、外部管理のロードバランサーやその他の依存リソースを削除してください。
これらが VPC の削除を妨げたり、料金を発生させ続けたりする場合があります。

再作成は上記の EKS コマンドで行います。クラスターオブジェクト、Secret、Job、および保存された
停止・復元アノテーションは失われます。アプリケーションマニフェストと Secret は通常の安全な
デプロイ手順で復元してください。NAT のパブリック IP は変わる可能性があるため、MongoDB などの
IP 許可リストを更新します。Fargate ログルーターと RBAC を再適用し、ワークロードと DNS を
確認してください。共有トピックを保持している場合、SNS のメール購読も残ります。

### 既存ローカル State の移行

所有権を分割するまで、apply または destroy を実行しないでください。既存 State を安全に
バックアップし、他の Terraform 操作を停止し、バックエンド、AWS アカウント、State 内容を
確認します。次の例は、表示されているモジュールアドレスを持つ以前のローカル
`terraform\terraform.tfstate` **だけ**を対象とします。別の State パス、リモートバックエンド、
古いリソースアドレスを使用している場合は、その State に合わせた移行手順を準備してください。
移行先と移行元の両方にリソースが存在する場合は、作業前に所有権を解決してください。

バックアップと確認後、移行先に State がない場合に限り、以前のローカル State を
`terraform\stacks\main\terraform.tfstate` へ移動します。両方のルートを適用せずに初期化します。
`terraform\stacks\main` から、既存の EKS 側モジュールを
`terraform state mv -state-out=..\eks\terraform.tfstate <module> <module>` で
`..\eks\terraform.tfstate` へ移動します。移行元 State に存在するモジュールだけを移動してください。

```text
module.network
module.eks
module.codebuild
module.fargate_control_network
module.fargate_control_access
module.fargate_control
module.fargate_control_bus
module.fargate_control_monitoring
module.fargate_control_schedule
```

| 共有 State に残すモジュール |
|---|
| `module.ecr` |
| `module.iam` |
| `module.cloudwatch` |
| `module.github_connection` |
| `module.codebuild_policy` |
| `module.fargate_control_iam` |
| `module.lambda_alerts` |

各 State 移動はファイルへ即座に反映されます。失敗した場合は
停止し、両方の State を確認してください。共有出力を更新し、apply の前に**両方**の plan を
確認してください。既存リソースが予期せず作成、削除、置換されていないことを確認します。
以前に `moved` ブロックなしで Fargate 制御のリファクタリングが行われていた場合は、
これらのモジュール移動前に追加のリソースアドレス移行が必要になることがあります。
State 移行は自動では実行されません。

EKS State に `module.codebuild_policy`、`module.fargate_control_iam`、
`module.lambda_alerts` が含まれている場合、これらは現在は共有 State に属します。
両方をバックアップし、共有 State に存在しないことを確認したうえで、`terraform\stacks\eks`
から `terraform state mv -state-out=..\main\terraform.tfstate <module> <module>` を
各モジュールに実行します。ポリシーには `module.codebuild_policy` を使用し、
存在する場合のインスタンスアドレスは `'module.fargate_control_iam[0]'`、
`'module.lambda_alerts[0]'` のようにクォートしてください。適用前に両方の plan を確認し、
SNS トピックや購読を再作成しないでください。CodeBuild ソースは現在 SSM から読み取られ、
共有ルートの `website_repository_url` が Fargate 制御 IAM の信頼設定を制御します。

EKS コントロールプレーン、NAT Gateway、インターフェイスエンドポイント、Fargate、ALB、
データ転送には料金が発生する可能性があります。適用前にコストを確認し、plan を完全に確認してください。

## Fargate モニタリング

Fargate Pod 実行ロールと30日間保持の CloudWatch Logs ロググループは Terraform で
プロビジョニングされます。適用後、アプリケーション Pod を作成する前に、EKS Kubernetes API
へアクセスできる管理者で Fargate ログルーターを設定します。

```powershell
terraform -chdir=terraform\stacks\eks output -raw fargate_logging_manifest | kubectl apply -f -
```

新しい Fargate Pod のコンテナ出力は `/aws/eks/<cluster-name>/fargate` へ送信されます。
既存 Pod に設定を反映するには再起動が必要です。アプリケーションログへ Secret や個人情報を
書き込まないでください。

| 監視対象 | 提供内容 | 対応しない内容 |
|---|---|---|
| Metrics Server | `kubectl top pods` の現在値（CPU、メモリ） | 履歴保存、CloudWatch メトリクス、アラーム |
| EKS コントロールプレーンログ | コントロールプレーンのログ | Pod モニタリングの代替 |
| Fargate 互換テレメトリコレクター | 履歴メトリクスとアラートの別途設定 | この構成では未導入 |

### Loki、Grafana、Alloy

可観測性用の umbrella chart は、専用の EKS Fargate プロファイルを持つ `monitoring`
名前空間へインストールされます。Alloy は Kubernetes API から Pod ログを読み取り Loki へ送信し、
Grafana が Loki を参照します。これは既存の CloudWatch ログルーターとは別物です。
| コンポーネント | 役割 | 制約 |
|---|---|---|
| Alloy | Kubernetes API から Pod ログを読み、Loki へ送信 | レプリカ1、障害中やローテーション後にログ欠損の可能性 |
| Loki | ログを S3 に保存し、検索できるよう管理 | サービス認証なし。プライベート維持が必須 |
| Grafana | Loki を参照して可視化 | ClusterIP のみ。ローカル DB は一時的 |
| Metrics | — | この構成は履歴メトリクスを収集しない |

main スタックが暗号化されたプライベート Loki S3 バケットを所有するため、
EKS を削除してもバケットは削除されません。

| オブジェクト状態 | ストレージクラス | 注意点 |
|---|---|---|
| 作成後0～30日 | S3 Standard | 即時アクセス可能 |
| 30日後 | Glacier Instant Retrieval | 移行・保存料金が発生 |
| 120日後 | Deep Archive | アクセス前に復元が必要 |
| 0バイト | S3 Standard のまま | ライフサイクル移行なし |
| 期限 | 自動削除なし | 別途バックアップが必要 |

必要なオブジェクトがアーカイブされている間、古い Loki クエリやインデックス圧縮が失敗する
可能性があります。S3 の移行、保存、復元には料金が発生し、小さなオブジェクトでは特に影響が
大きい場合があります。このアーカイブに依存する前に復元手順をテストしてください。

Loki はレプリカ1台と一時的なローカルストレージを WAL に使用します。フラッシュされていない
ログは、フラッシュ済みデータが S3 にあっても Pod の突然の停止で失われる場合があります。
Grafana のローカルデータベースも一時的なため、UI で作成したダッシュボードや変更は Pod の
置換時に失われます。Loki サービスには認証がないため、必ずプライベートのままにしてください。
Grafana は ClusterIP サービスのみで公開されます。

main スタックを先に適用し、両方の plan を確認してから EKS スタックを適用してください。
EKS スタックはクラスター OIDC プロバイダーと、バケットおよび
`monitoring/loki` サービスアカウントに限定された Loki IAM ロールを作成します。
クラスターの OIDC プロバイダーがすでに他で管理されている場合は、適用前に import するか、
所有権を調整してください。main の plan にある CodeBuild IAM ポリシーの `moved` ブロックも
確認してください。

イメージをミラーリングするには、main スタックの ECR push ロール変更を適用し、
`Image Push` ワークフローを `main` へ公開します。このワークフローは GitHub の
`ACCOUNT_ID` Secret、`infra-eks-webhost-ecr-push-role` ロール、
`ap-southeast-2` を使用します。OIDC の信頼設定は、GitHub の不変の所有者 ID とリポジトリ ID
を用いて、このリポジトリの `main` ブランチだけを許可します。OIDC subject 形式を変更した場合は、
ワークフロー実行前に信頼ポリシーを更新してください。GitHub Actions では、完全なソース
イメージ参照、既存の ECR リポジトリ名、対象タグを指定して実行します。例:
`grafana/alloy:v1.22.0`、`infra-eks-webhost-alloy`、`v1.22.0`。
ECR タグは不変であり、既存タグを再度 push すると失敗します。現在のロールは、設定された
アカウントとリージョン内のリポジトリへ広範な ECR アクセスを許可します。

| コンポーネント | ソースイメージ |
|---|---|
| Grafana | `grafana/grafana:12.3.1` |
| Loki | `grafana/loki:3.7.10` |
| Alloy | `grafana/alloy:v1.22.0` |

デプロイ前に上記イメージを同じタグで既存のプライベート ECR リポジトリへミラーリングします。
`monitoring` 名前空間と、`admin-user` および `admin-password` を格納した `grafana-admin`
Secret を、安全なシークレット管理手順で作成してください。認証情報をコミットしないでください。
その後、リポジトリルートから次を実行します。

```powershell
helm dependency build k8s\helm\grafana
$shared = terraform -chdir=terraform\stacks\main output -json eks_shared | ConvertFrom-Json
$role = terraform -chdir=terraform\stacks\eks output -raw loki_role_arn
$registry = ($shared.ecr_repository_url -split '/')[0]
$bucket = $shared.loki_bucket_name
$project = $shared.project_name
helm upgrade --install observability k8s\helm\grafana --namespace monitoring `
  -f k8s\helm\loki\values.yaml -f k8s\helm\alloy\values.yaml `
  --set-string "grafana.image.registry=$registry" `
  --set-string "grafana.image.repository=$project-grafana" `
  --set-string "loki.loki.image.registry=$registry" `
  --set-string "loki.loki.image.repository=$project-loki" `
  --set-string "alloy.image.registry=$registry" `
  --set-string "alloy.image.repository=$project-alloy" `
  --set-string "loki.loki.storage.s3.region=$($shared.aws_region)" `
  --set-string "loki.loki.storage.bucketNames.chunks=$bucket" `
  --set-string "loki.loki.storage.bucketNames.ruler=$bucket" `
  --set-string "loki.serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$role"
```

Pod の Ready 状態と Alloy/Loki のログを確認し、
`kubectl -n monitoring port-forward svc/grafana 3000:80` でローカルから Grafana へ
アクセスしてください。EKS クラスターを再作成した場合は、Loki IAM ロールの再作成と
チャートの再インストールが必要です。

MongoDB ネットワーク許可リスト用の固定送信元 IP を確認するには、適用後にリポジトリルートで
`terraform -chdir=terraform\stacks\eks output -raw network_gateway_public_ip`
を実行します。必要に応じて、このアドレスを MongoDB 環境で許可してください。
接続文字列や認証情報を Terraform 変数、State、ログ、コンテナイメージに保存しないでください。

## Fargate の定期停止と復元

任意の Lambda は、**すべて**の Fargate プロファイルセレクターを検出して処理します。

| リソース | 停止時の処理 | 復元時の挙動 |
|---|---|---|
| CronJob | `suspend` 状態をアノテーションへ保存して停止 | 元の状態へ復元 |
| Deployment / StatefulSet | レプリカ数を保存して0へ縮小 | 元のレプリカ数へ復元（元が0の場合も保持） |
| 未完了 Job | 削除 | 再作成しない |
| Pod | 削除 | 再作成しない |
| Fargate ノード | 消失するまで待機 | ワークロード復元後に再作成 |

対象には CoreDNS、Metrics Server、ウェブサイトワークロードが含まれます。
ウェブサイトアクセス、クラスター DNS、監視、定期ジョブが停止し、中断された Job は再開されません。
EKS コントロールプレーン、NAT Gateway、エンドポイントなどは引き続き料金が発生します。

新しく作成された Pod、オートスケーラー、Deployment、またはアドオンの調整により、ワークロードが
再作成される場合があります。停止期間中は自動デプロイとスケーリングを無効にしてください。
待機後も一致する Pod または Fargate ノードが残った場合、Lambda は失敗します。

停止時の以前のレプリカ数と CronJob の停止状態は、各リソースのアノテーションとして保存されます。
復元操作はこれらを元に戻します。元のレプリカ数が0の場合や、もともと停止済みの CronJob も
含まれます。削除済みの Job、スタンドアロン Pod、停止中に削除または置換されたリソースは再作成
されません。停止中に `fargate-control.kfrost533.dev/previous-state` アノテーションを削除したり、
Helm upgrade を実行したりしないでください。復元要求はアプリケーションや DNS の Ready 状態を
待たないため、実行後にクラスターを確認してください。

設定手順:

1. Node.js 22 と npm を使用し、リポジトリルートから関数をビルドします。
   ```powershell
   Set-Location terraform\modules\eks\fargate-control\lambda
   npm ci
   npm run build
   npm run typecheck
   npm test
   Set-Location ..\..\..\..\..
   ```
   Lambda ソースを変更して適用する前に、毎回ビルドしてください。生成された `dist` バンドルはコミットされません。
2. `terraform\stacks\main\terraform.tfvars` で `enable_fargate_control = true` を設定し、共有ルートを適用します。IAM と SNS トピックが作成されます。`terraform\stacks\eks\terraform.tfvars` の `enable_fargate_stop_schedule = false` はそのままにし、Lambda、ネットワークアクセス、イベントバス、アラーム、**無効化された**スケジュールを EKS plan で確認して適用します。Lambda はリージョナル EKS API へ VPC NAT 経由で接続し、既存の STS エンドポイントを使用します。
3. 対象クラスターの管理者 kubeconfig を使用し、リポジトリルートで `kubectl apply -f terraform\modules\eks\fargate-control\lambda\scaler-rbac.yaml` を適用します。これは IAM とは別に、Lambda の EKS access-entry グループへクラスター全体の list/patch/delete 権限を付与します。対象クラスターを確認し、マニフェストをレビューしてください。
4. SNS コンソールで、`terraform -chdir=terraform\stacks\eks output -raw lambda_alerts_topic_arn` が示すトピックへメール購読を作成し、メール内のリンクで確認します。確認前は通知が配信されません。
5. GitHub リポジトリ設定で、Secret `FARGATE_RESTORE_ROLE_ARN` に `terraform -chdir=terraform\stacks\eks output -raw fargate_restore_role_arn` の値を設定します。変数 `AWS_REGION` にはデプロイリージョンを、`FARGATE_CONTROL_BUS_NAME` には `terraform -chdir=terraform\stacks\eks output -raw fargate_control_bus_name` の値を設定します。設定されたリポジトリの `main` ブランチだけがロールを引き受けられ、制御バスへ一致するイベントを送信できますが、Lambda を直接呼び出すことはできません。main ブランチとワークフローを保護してください。
6. 管理されたメンテナンス時間帯に `main` の **Control EKS Fargate** を `stop` で実行し、対応する CloudWatch ログとアラームを確認してから `start` で実行します。元のレプリカ数、CronJob 状態、Pod の Ready 状態、DNS を確認してください。タイムアウトや部分的な失敗で一部のワークロードが停止したままになる場合があるため、再実行前にログを確認してください。
7. テスト成功後にのみ `enable_fargate_stop_schedule = true` へ変更し、plan を確認して適用します。EventBridge Scheduler は毎日 **17:00 Asia/Tokyo** に停止エイリアスを呼び出します。スケジュールを停止するには変数を `false` に戻して適用します。

GitHub Actions が確認するのは、EventBridge がリクエストを受け付けたことだけです。
ルールに一致したことや Lambda が完了したことまでは確認できません。リクエスト ID を
`/aws/lambda/<project>-fargate-control` ログで検索し、`FARGATE_CONTROL_SUCCESS` または
`FARGATE_CONTROL_FAILURE` を確認してください。ワークロードの Ready 状態は別途確認します。
EventBridge と Lambda は非同期配信であり、イベントの重複や遅延が発生する場合があります。
停止・開始リクエストを重複させず、次の要求を出す前に結果を確認してください。
再試行は無効でイベント有効期限は60秒ですが、順序保証や exactly-once 実行はありません。
設定されたバス名も確認してください。EventBridge は存在しないバス宛てのイベントも受け付ける一方、
配信されないことがあります。

再利用可能な Lambda 監視モジュールは composite alarm を通じて SNS 通知を送信します。

| 監視元 | 検出対象 |
|---|---|
| CloudWatch Logs メトリクスフィルター | 関数の明示的な失敗マーカー |
| Lambda `Errors` | 実行時エラー、タイムアウト |
| Lambda `Throttles` | スロットリング |
| Lambda `AsyncEventsDropped` | 非同期イベントの破棄 |
| EventBridge `FailedInvocations` | Lambda への配信失敗 |
| EventBridge Scheduler | Lambda 呼び出し前の配信失敗は対象外 |

CloudWatch/EventBridge のメトリクスと配信は保証された
監査記録ではないため、ログを確認し、結果を検証してください。
composite alarm は ALARM への遷移時に通知しますが、ALARM 中の障害ごとには通知しません。
追加のログメトリクス、アラーム、SNS 通知、EventBridge 使用には料金が発生する可能性があります。
別の Lambda を監視するには、ロググループ、失敗フィルターパターン、トピックを指定して
監視モジュールをインスタンス化します。この構成には他の Lambda 関数は設定されていません。

## 週次 YouTube CSV メール

| 項目 | 内容 |
|---|---|
| 実行日時 | 毎週月曜日 09:00 `Asia/Tokyo` |
| 対象 | 保存済みのすべての YouTube 検索結果行 |
| 出力 | BOM 付き UTF-8 CSV |
| 上限 | 添付ファイル6 MiB |
| 検索 | 実行しない |
| 重複除去 | 実行しない |
| 日次検索スケジューラー | 変更なし、別プロセス |
| 必要な接続 | MongoDB、SES SMTP、DNS、TCP 587 |

CSV には日付、キーワード、動画 ID、タイトル、URL、チャンネル、公開日が含まれます。
スプレッドシートの数式として解釈されそうな値はエスケープされます。
CSV 全体が上限を超える場合は、部分的なレポートを送信せず失敗します。

有効化前の準備:

1. SMTP エンドポイントと同じリージョンの Amazon SES で送信元 ID を検証します。SES サンドボックス内では受信者も検証し、送信クォータを確認し、必要に応じて本番アクセスを申請してください。
2. 検証済み ID から送信する最小権限の SES SMTP 認証情報を、リージョンに合わせて作成します。SMTP 認証情報は通常の AWS アクセスキーとは異なります。
3. 安全なシークレット管理手順で、`website` 名前空間に `youtube-report-ses` Kubernetes Secret を作成し、次のキーを設定します。

   | キー | 値 |
   |---|---|
   | `REPORT_SMTP_HOST` | リージョナル SES SMTP ホスト名。例: `email-smtp.ap-southeast-1.amazonaws.com` |
   | `REPORT_SMTP_USER` | SES SMTP ユーザー名 |
   | `REPORT_SMTP_PASS` | SES SMTP パスワード |
   | `REPORT_SMTP_FROM` | 検証済みの送信元メールアドレス |
   | `REPORT_TO` | 1つの受信者メールアドレス |

   これらの値をコミットしたり、Terraform 変数に入れたり、シェルコマンドの引数として渡したりしないでください。Secret へのアクセスを制限し、Kubernetes Secret の保存時データを保護してください。このジョブは既存の `website-secrets` Secret 内の `ACCESS_MONGODB_URI` キーを再利用します。
4. プライベート Fargate ワークロードが NAT 経由で MongoDB と SES SMTP エンドポイントへ接続できることを確認します。DNS と送信 TCP 587 が必要で、接続は STARTTLS を使用します。
5. `terraform\stacks\eks\terraform.tfvars` で `enable_weekly_report = true` を設定し、EKS Terraform plan を確認して適用し、CodeBuild デプロイを実行します。CodeBuild は各デプロイでこの設定を Helm に渡します。false のままにすると CronJob は無効です。手動 Helm デプロイでは `weeklyReport.enabled=true` を設定し、イメージ値を維持してください。

このジョブでは、接続失敗の前に SES がメールを受け付けている可能性があるため、
失敗後の自動再試行を行いません。Kubernetes のスケジュールは best effort であり、
長時間のクラスター障害やネットワーク障害で実行を逃す可能性があります。
`kubectl get cronjob -n website` と `kubectl get jobs -n website` を確認し、
失敗した Job のログは Secret の値を表示しないよう注意して調査してください。
必要に応じて、別途 Job 失敗アラートと SES の配信・バウンス監視を設定します。
SES が受け付けたことは配信完了を保証せず、Job の手動再実行で重複メールが送信される可能性があります。

## CI の準備

`/eks/video-platform-app` で指定されたリポジトリへの `main` push は、デフォルトで CodeBuild を
起動し EKS へデプロイします。MongoDB 接続と Secret の準備を確認するまで自動デプロイを延期するには、
適用前に `terraform\stacks\eks\terraform.tfvars` で
`enable_github_webhook = false` を設定します。対象リポジトリにリポジトリ内容、アプリケーション、
buildspec、チャートが存在する必要があります。push 前にすべてのステージ済みファイルを確認してください。
ignore ファイルだけでは Secret や機密データのチェックを代替できません。

| CI 項目 | 設定 |
|---|---|
| CodeBuild イメージ | `aws/codebuild/standard:7.0` |
| Helm | 3.17.3 |
| ダウンロード元 | `get.helm.sh` |
| 整合性確認 | 固定 SHA-256 |
| 必要な外部通信 | HTTPS |
| 既存ビルドツール ECR | main スタックで保持管理（CodeBuild は未使用） |

既存プロジェクトが EKS スタック更新まで動作を継続できるよう、CodeBuild ロールには
ビルドツールイメージを pull する権限が残っています。

| 手順 | 実施内容 |
|---:|---|
| 1 | AWS コンソールで GitHub CodeConnections を承認し、GitHub App のリポジトリアクセスと Webhook 権限を承認 |
| 2 | 管理者 kubeconfig で Fargate ログルーターを設定し、`website` 名前空間を作成 |
| 3 | MongoDB とバックアップを設定し、`website-secrets` に `ACCESS_MONGODB_URI` と `API_KEY_ENCRYPTION_KEY` を安全に保存 |
| 4 | 検証後に `enable_github_webhook` を有効化し、EKS plan を確認して適用 |

CodeBuild ロールは意図的に `website` 名前空間内のリソース編集だけに制限されています。
Secret 値をコミットしたり、Helm values や Terraform State に保存したりしないでください。
暗号化キーは固定しておいてください。Webhook を停止するには false に設定して適用します。

buildspec はソースコミットと一意のビルド ID をタグにしたイメージをビルド・pushし、
`helm upgrade --install` を実行します。並行ビルドや再試行により、新しいコミットの後に古い
コミットがデプロイされる可能性があります。CodeBuild プロジェクトの同時実行数を1にしても
キューにはなりません。1件の実行中に追加ビルドが開始されると拒否されます。
自動リリースを有効にする前に、デプロイ順序と再試行処理を設計・検証してください。
Helm チャートは Fargate Pod にデプロイされます。パブリックアクセスには AWS Load Balancer
Controller のインストールと、準備完了後のチャート Ingress 有効化が必要です。

| アプリケーション確認項目 | 状態・要件 |
|---|---|
| データベース | Mongoose で MongoDB へ直接接続 |
| SQLite 移行 | 既存データはインポートされない |
| Pod 起動条件 | Secret が事前に必要 |
| デプロイ前検証 | 接続性、権限、バックアップ、復旧 |
| 運用監視 | MongoDB 接続数とエラー |
| 接続プール調整 | ワークロードと容量を観測してから実施 |
| 公開方針 | 適切な認証設計なしで管理エンドポイントを公開しない |
