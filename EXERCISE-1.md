# Exercise 1: P4Runtime の基礎

この演習では、P4Runtime APIの実践的な紹介を提供します。以下の作業を行います：

1. P4スターターコードを確認する
2. BMv2ソフトウェアスイッチ用にコンパイルし、出力（P4InfoとBMv2 JSONファイル）を理解する
3. `stratum_bmv2`スイッチの2x2トポロジーでMininetを開始する
4. P4Runtime Shellを使用して、ホスト間の接続を提供するためにスイッチの1つにテーブルエントリを手動で挿入する

## 1. P4プログラムを確認する

まず、P4プログラムを確認しましょう：
[p4src/main.p4](p4src/main.p4)

残りの演習では、IPv6ベースのリーフ・スパインデータセンターファブリックを構築するよう求められます。作業を簡単にするため、以下の内容を含むスターターP4プログラムを提供しています：

* ヘッダー定義
* パーサー実装
* イングレスとエグレスパイプライン実装（不完全）
* チェックサム検証/更新

実装では、L2ブリッジングとACL動作のロジックが既に提供されています。プログラム全体を**簡単に確認**して構造を理解することをお勧めします。完了したら、P4プログラムを参照して詳細を理解しながら、以下の質問に答えてみてください。

**パーサー**

* パケットから抽出できるプロトコルヘッダーをすべてリストアップしてください。
* 新しいパケットを解析する際に最初に期待されるヘッダーはどれですか？

**イングレスパイプライン**

* L2ブリッジングの場合、NDPリクエストをすべてのホスト向けポートに複製するためにどのテーブルが使用されますか？そのテーブルではどのタイプのマッチが使用されますか？
* ACLテーブルで、`send_to_cpu`と`clone_to_cpu`アクションの違いは何ですか？
* applyブロックで、パケットに最初に適用されるテーブルはどれですか？P4Runtimeパケットアウトは異なる処理をされますか？

**エグレスパイプライン**

* マルチキャストパケットは、入力ポートに複製できますか？

**デパーサー**

* ワイヤ上で最初にシリアライズされるヘッダーは何で、どの場合ですか？

## 2. P4プログラムをコンパイルする

次のステップは、BMv2 `simple_switch`ターゲット用にP4プログラムをコンパイルすることです。このために、この特定のターゲット用のバックエンド`p4c-bm2-ss`を含むオープンソースP4_16コンパイラー（[p4c][p4c]）を使用します。

プログラムをコンパイルするには、演習VMでターミナルウィンドウを開き、以下のコマンドを入力してください：

```
make p4-build
```

以下のような出力が表示されるはずです：

```
*** Building P4 program...
docker run --rm -v /home/sdn/ngsdn-tutorial:/workdir -w /workdir
 opennetworking/p4c:stable \
                p4c-bm2-ss --arch v1model -o p4src/build/bmv2.json \
                --p4runtime-files p4src/build/p4info.txt --Wdisable=unsupported \
                p4src/main.p4
*** P4 program compiled successfully! Output files are in p4src/build
```

Makefileは`p4c-bm2-ss`コンパイラーをコンテナ化されたバージョンで使用するようにインストゥルメントされています。`p4c-bm2-ss`を呼び出す際の引数を確認すると、コンパイラーに以下を指示していることがわかります：

* v1modelアーキテクチャー（`--arch`引数）をコンパイルする；
* メイン出力を`p4src/build/bmv2.json`に配置する（`-o`）；
* `p4src/build/p4info.txt`にP4Infoファイルを生成する（`--p4runtime-files`）；
* サポートされていない機能に関する警告を無視する（`--Wdisable=unsupported`）。
  これらの警告はp4cのバグによって生成されるため、ここでは無視してもかまいません。

### コンパイラー出力

#### bmv2.json

このファイルは、BMv2 `simple_switch`ターゲットの設定をJSON形式で定義します。`simple_switch`が新しいパケットを受信すると、この設定を使用してパケットを処理します。

これはかなり大きなファイルですが、この演習のためにその内容を理解する必要はありません。より詳細に学びたい場合は、BMv2 JSONフォーマットの仕様を以下で提供しています：
<https://github.com/p4lang/behavioral-model/blob/master/docs/JSON_format.md>

#### p4info.txt

このファイルは、P4プログラムのP4InfoスキーマのインスタンスをProtobuf Text形式で表現します。

このファイルを確認し、以下の質問に答えてみてください：

1. `l2_exact_table`の完全修飾名は何ですか？その数値IDは何ですか？
2. ID `16812802`は、テーブル、アクション、またはその他のものに属しますか？対応する完全修飾名は何ですか？
3. `IngressPipeImpl.set_egress_port`アクションの場合、このアクションに定義されているパラメータはいくつありますか？パラメータ名`port_num`のビット幅はいくつですか？
4. ファイルの最後に、`packet_out`という名前の`controller_packet_metadata`メッセージの定義を探してください。次に、P4プログラムの`header cpu_out_header_t`の定義を探してください。2つの定義に関係がありますか？

## 3. Mininetトポロジーを開始する

これで、`stratum_bmv2`スイッチのエミュレートネットワークを開始する時期です。前のステップで得られたコンパイラー出力を使用して、1つのスイッチをプログラムします。

トポロジーを開始するには、以下のコマンドを使用します：

```
make start
```

このコマンドは2つのDockerコンテナを起動します：1つはmininet用、もう1つはONOS用です。現在はONOSコンテナは無視してください。

コンテナがエラーなしで起動されたことを確認するために、`make mn-log`コマンドを使用してMininetログを表示できます。以下の出力を確認してください（Ctrl-Cで終了）：

```
$ make mn-log
docker-compose logs -f mininet
Attaching to mininet
mininet    | *** Error setting resource limits. Mininet's performance may be affected.
mininet    | *** Creating network
mininet    | *** Adding hosts:
mininet    | h1a h1b h1c h2 h3 h4
mininet    | *** Adding switches:
mininet    | leaf1 leaf2 spine1 spine2
mininet    | *** Adding links:
mininet    | (h1a, leaf1) (h1b, leaf1) (h1c, leaf1) (h2, leaf1) (h3, leaf2) (h4, leaf2) (spine1, leaf1) (spine1, leaf2) (spine2, leaf1) (spine2, leaf2)
mininet    | *** Configuring hosts
mininet    | h1a h1b h1c h2 h3 h4
mininet    | *** Starting controller
mininet    |
mininet    | *** Starting 4 switches
mininet    | leaf1 stratum_bmv2 @ 50001
mininet    | leaf2 stratum_bmv2 @ 50002
mininet    | spine1 stratum_bmv2 @ 50003
mininet    | spine2 stratum_bmv2 @ 50004
mininet    |
mininet    | *** Starting CLI:
```

"*** Error setting resource limits..."は無視してください。

mininetコンテナの起動パラメータは[docker-compose.yml](docker-compose.yml)で指定されています。コンテナは[mininet/topo-v6.py](mininet/topo-v6.py)で定義されたトポロジースクリプトを実行するように設定されています。

トポロジーには4つのスイッチが含まれており、2x2ファブリックトポロジーで配置されています。また、リーフスイッチに6つのホストが接続されています。3つのホスト`h1a`、`h1b`、`h1c`は、同じIPv6サブネットに属しています。次のステップでは、このサブネット内の2つのホスト間でpingを行うためにP4Runtimeを使用してテーブルエントリを挿入するよう求められます。

![topo-v6](img/topo-v6.png)

### stratum_bmv2一時ファイル

Mininetコンテナを起動する際に、各`stratum_bmv2`インスタンスの実行に関連するファイルが`tmp`ディレクトリに生成されます。例としては：

* `tmp/leaf1/stratum_bmv2.log`：スイッチ`leaf1`のstratum_bmv2ログを含む；
* `tmp/leaf1/chassis-config.txt`：スイッチ起動時に使用する初期ポート設定を指定するStratumの"チャーシス設定"ファイル。このファイルは`StratumBmv2Switch`クラスが[mininet/topo-v6.py](mininet/topo-v6.py)で呼び出された際に自動的に生成されます。
* `tmp/leaf1/write-reqs.txt`：スイッチが処理したすべてのP4Runtime書き込みリクエストのログ（スイッチが書き込みリクエストを受信していない場合、このファイルは存在しない可能性があります）。

## 4. leaf1をP4Runtimeでプログラムする

この部分では、[P4Runtime Shell][p4runtime-sh]を使用します。これは、P4Runtimeサーバーに接続し、P4Runtimeコマンドを実行できるインタラクティブなPython CLIです。例えば、フロータブルエントリを作成、読み取り、更新、削除できます。

シェルは2つのモードで起動できます：P4パイプライン設定を使用する場合と使用しない場合です。最初の場合、シェルは指定されたパイプライン設定をスイッチにプッシュするためにP4Runtime `SetPipelineConfig` RPCを使用します。2番目の場合、シェルはスイッチに現在設定されているP4Infoを取得しようとします。

どちらの場合も、シェルはP4Infoファイルを使用して：
* P4Info名を使用してランタイムエンティティ（テーブルエントリなど）を指定することを可能にします（数値IDよりもはるかに簡単で読みやすい）；
* オートコンプリートを提供します；
* CLIコマンドを検証します。

最後に、P4Runtimeサーバーに接続する際に、マスターシップ選挙IDを提供する必要があります。これにより、パイプライン設定やテーブルエントリなどの状態を書き込むことができます。

P4Runtime Shellを`leaf1`に接続し、前のステップで得られたパイプライン設定をプッシュするには、以下のコマンドを使用します：

```
util/p4rt-sh --grpc-addr localhost:50001 --config p4src/build/p4info.txt,p4src/build/bmv2.json --election-id 0,1
```

`util/p4rt-sh`は、指定された引数でP4Runtime Shell Dockerコンテナを呼び出す簡単なPythonスクリプトです。引数のリストを表示するには`util/p4rt-sh --help`を使用してください。

**注意：** Mininetコンテナはローカルで実行されているため、`--grpc-addr localhost:50001`を使用します。また、`50001`は`leaf1`によって公開されているgRPCサーバーに関連付けられたTCPポートです。

シェルが正常に起動した場合、以下の出力が表示されます：

```
*** Connecting to P4Runtime server at host.docker.internal:50001 ...
*** Welcome to the IPython shell for P4Runtime ***
P4Runtime sh >>>
```

#### 利用可能なコマンド

`tables`、`actions`、`action_profiles`、`counters`、`direct_counters`など、P4Infoメッセージフィールドに名前が付けられたコマンドを使用して、P4Infoオブジェクトに関する情報を照会します。

`table_entry`、`action_profile_member`、`action_profile_group`、`counter_entry`、`direct_counter_entry`、`meter_entry`、`direct_meter_entry`、`multicast_group_entry`、`clone_session_entry`などのコマンドを使用して、対応するP4Runtimeエンティティを読み書きできます。

コマンド名の後に`?`を付けて、各コマンドの情報を表示します。例：`table_entry?`。

P4Runtime Shellの詳細については、公式ドキュメントを参照してください：
<https://github.com/p4lang/p4runtime-shell>

シェルは`tab`キーを押すとオートコンプリートをサポートします。例えば：

```
tables["IngressPipeImpl.<tab>
```

は`IngressPipeImpl`ブロック内で定義されたすべてのテーブルを表示します。

### ブリッジング接続性テスト

leaf1で必要なP4Runtimeテーブルエントリを挿入した後、接続性を確認するには、Mininet CLIを使用します。

新しいターミナルウィンドウで、`make mn-cli`を使用してMininet CLIにアタッチします。

以下の出力が表示されるはずです：

```
*** Attaching to Mininet CLI...
*** To detach press Ctrl-D (Mininet will keep running)
mininet>
```

### 静的NDPエントリを挿入する

同じサブネット内の2つのIPv6ホスト間でpingを行うためには、まず、ホストがそれぞれのMACアドレスをNeighbor Discovery Protocol（NDP）を使用して解決する必要があります。これはIPv4ネットワークでのARPと同様です。例えば、`h1b`から`h1a`にpingを試みる場合、`h1a`はまず`h1b`のMACアドレスを解決するためにNDP Neighbor Solicitation（NS）メッセージを生成します。`h1b`がNDP NSメッセージを受信すると、`h1b`は自分のMACアドレスを持つNDP Neighbor Advertisement（NA）メッセージを返信するはずです。これで、両方のホストは互いのMACアドレスを認識し、pingパケットを交換できるようになります。

P4プログラムを前に確認したとき、スイッチがNDPパケットを正しくP4Runtimeを使用してプログラムすることができるはずです（`l2_ternary_table`を参照）。ただし、**現在は簡単にするために、ホストに2つの静的NDPエントリを挿入します。**

`h1a`に`h1b`のIPv6アドレス（`2001:1:1::b`）を`h1b`のMACアドレス（`00:00:00:00:00:1B`）にマッピングするNDPエントリを追加します：

```
mininet> h1a ip -6 neigh replace 2001:1:1::B lladdr 00:00:00:00:00:1B dev h1a-eth0
```

そして、`h1b`に`h1a`のアドレスを解決するためにNDPエントリを追加します：

```
mininet> h1b ip -6 neigh replace 2001:1:1::A lladdr 00:00:00:00:00:1A dev h1b-eth0
```

### pingを開始する

`h1a`と`h1b`の間でpingを開始します。P4Runtimeテーブルエントリを挿入していないため、パケットを転送できません。

```
mininet> h1a ping h1b
```

pingコマンドからの出力はありません。このコマンドを現在は残しておきます。

### P4Runtimeテーブルエントリを挿入する

`leaf1`の`l2_exact_table`に2つのエントリを追加する必要があります--1つは`h1b`の宛先MACアドレスに一致し、ポート4（`h1b`が接続されているポート）にトラフィックを転送し、その逆（`h1a`がポート3に接続されている）。

P4Runtimeシェルを使用して、以下の2つのエントリを`l2_exact_table`に挿入します。P4Infoファイルを参照して、以下の2つのエントリを挿入します：

| マッチ（Ethernet dest） | エグレスポート番号  |
|-----------------------|-------------------- |
| `00:00:00:00:00:1B`   | 4                   |
| `00:00:00:00:00:1A`   | 3                   |

テーブルエントリオブジェクトを作成するには：

```
P4Runtime sh >>> te = table_entry["P4INFO-TABLE-NAME"](action = "<P4INFO-ACTION-NAME>")
```

各エンティティの完全修飾名を使用することを確認してください。例：`IngressPipeImpl.l2_exact_table`、`IngressPipeImpl.set_egress_port`など。

マッチフィールドを指定するには：

```
P4Runtime sh >>> te.match["P4INFO-MATCH-FIELD-NAME"] = ("VALUE")
```

`VALUE`はコロン16進数表記のMACアドレス（例：`00:11:22:AA:BB:CC`）、またはドット表記のIPアドレス、または任意の文字列にすることができます。P4Infoに含まれる情報に基づいて、P4Runtimeシェルは内部でその値をProtobufバイト文字列に変換します。

テーブルエントリアクションパラメータの値を指定するには：

```
P4Runtime sh >>> te.action["P4INFO-ACTION-PARAM-NAME"] = ("VALUE")
```

テーブルエントリオブジェクトをProtobuf Text形式で表示するには、`print`コマンドを使用します：

```
P4Runtime sh >>> print(te)
```

シェルはP4Infoファイルの内容を使用して、対応するProtobufメッセージのフィールドを自動的に埋めます。

エントリを挿入する（これはスイッチへのP4Runtime書き込みRPCを発行します）：

```
P4Runtime sh >>> te.insert()
```

エントリを読み取る（これはP4Runtime読み取りRPCを発行します）：

```
P4Runtime sh >>> for te in table_entry["P4INFO-TABLE-NAME"].read():
            ...:     print(te)
            ...:
```

2つのエントリを挿入した後、pingが機能するはずです。Mininet CLIターミナルに戻り、pingコマンドを実行して、以下のような出力を確認してください：

```
mininet> h1a ping h1b
PING 2001:1:1::b(2001:1:1::b) 56 data bytes
64 bytes from 2001:1:1::b: icmp_seq=956 ttl=64 time=1.65 ms
64 bytes from 2001:1:1::b: icmp_seq=957 ttl=64 time=1.28 ms
64 bytes from 2001:1:1::b: icmp_seq=958 ttl=64 time=1.69 ms
...
```

## おめでとうございます！

この演習を完了しました！Mininetを実行したままにしてください。次の演習で使用します。

[p4c]: https://github.com/p4lang/p4c
[p4runtime-sh]: https://github.com/p4lang/p4runtime-shell
