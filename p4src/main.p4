/*
 * Copyright 2019-present Open Networking Foundation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


#include <core.p4>
#include <v1model.p4>

// CPU_PORTは、コントローラーのパケットインとパケットアウトに関連付けられたP4ポート番号を指定します。
// このポート経由で転送されるすべてのパケットは、P4Runtime PacketInメッセージとしてコントローラーに配信されます。
// 同様に、コントローラーからのPacketOutメッセージは、P4パイプラインからCPU_PORTからのものとして認識されます。
#define CPU_PORT 255

// CPU_CLONE_SESSION_IDは、CPUポートにクローンされるパケットのミラーリングセッションを指定します。
// このセッションIDに関連付けられたパケットは、CPU_PORTにクローンされると同時に、
// その出力ポート（ブリッジング/ルーティング/ACLテーブルによって設定）経由で送信されます。
// クローニングが機能するためには、P4Runtimeコントローラーが最初にこのセッションIDをCPU_PORTに
// マッピングするCloneSessionEntryを挿入する必要があります。
#define CPU_CLONE_SESSION_ID 99

// SRv6を使用する際にサポートされる最大ホップ数。
// Exercise 7で必要。
#define SRV6_MAX_HOPS 4

typedef bit<9>   port_num_t;
typedef bit<48>  mac_addr_t;
typedef bit<16>  mcast_group_id_t;
typedef bit<32>  ipv4_addr_t;
typedef bit<128> ipv6_addr_t;
typedef bit<16>  l4_port_t;

const bit<16> ETHERTYPE_IPV4 = 0x0800;
const bit<16> ETHERTYPE_IPV6 = 0x86dd;

const bit<8> IP_PROTO_ICMP   = 1;
const bit<8> IP_PROTO_TCP    = 6;
const bit<8> IP_PROTO_UDP    = 17;
const bit<8> IP_PROTO_SRV6   = 43;
const bit<8> IP_PROTO_ICMPV6 = 58;

const mac_addr_t IPV6_MCAST_01 = 0x33_33_00_00_00_01;

const bit<8> ICMP6_TYPE_NS = 135;
const bit<8> ICMP6_TYPE_NA = 136;

const bit<8> NDP_OPT_TARGET_LL_ADDR = 2;

const bit<32> NDP_FLAG_ROUTER    = 0x80000000;
const bit<32> NDP_FLAG_SOLICITED = 0x40000000;
const bit<32> NDP_FLAG_OVERRIDE  = 0x20000000;


//------------------------------------------------------------------------------
// ヘッダー定義
//------------------------------------------------------------------------------

header ethernet_t {
    mac_addr_t  dst_addr;
    mac_addr_t  src_addr;
    bit<16>     ether_type;
}

header ipv4_t {
    bit<4>   version;
    bit<4>   ihl;
    bit<6>   dscp;
    bit<2>   ecn;
    bit<16>  total_len;
    bit<16>  identification;
    bit<3>   flags;
    bit<13>  frag_offset;
    bit<8>   ttl;
    bit<8>   protocol;
    bit<16>  hdr_checksum;
    bit<32>  src_addr;
    bit<32>  dst_addr;
}

header ipv6_t {
    bit<4>    version;
    bit<8>    traffic_class;
    bit<20>   flow_label;
    bit<16>   payload_len;
    bit<8>    next_hdr;
    bit<8>    hop_limit;
    bit<128>  src_addr;
    bit<128>  dst_addr;
}

header srv6h_t {
    bit<8>   next_hdr;
    bit<8>   hdr_ext_len;
    bit<8>   routing_type;
    bit<8>   segment_left;
    bit<8>   last_entry;
    bit<8>   flags;
    bit<16>  tag;
}

header srv6_list_t {
    bit<128>  segment_id;
}

header tcp_t {
    bit<16>  src_port;
    bit<16>  dst_port;
    bit<32>  seq_no;
    bit<32>  ack_no;
    bit<4>   data_offset;
    bit<3>   res;
    bit<3>   ecn;
    bit<6>   ctrl;
    bit<16>  window;
    bit<16>  checksum;
    bit<16>  urgent_ptr;
}

header udp_t {
    bit<16> src_port;
    bit<16> dst_port;
    bit<16> len;
    bit<16> checksum;
}

header icmp_t {
    bit<8>   type;
    bit<8>   icmp_code;
    bit<16>  checksum;
    bit<16>  identifier;
    bit<16>  sequence_number;
    bit<64>  timestamp;
}

header icmpv6_t {
    bit<8>   type;
    bit<8>   code;
    bit<16>  checksum;
}

header ndp_t {
    bit<32>      flags;
    ipv6_addr_t  target_ipv6_addr;
    // NDP option.
    bit<8>       type;
    bit<8>       length;
    bit<48>      target_mac_addr;
}

// パケットインヘッダー。CPU_PORTに送信されるパケットに前置され、
// P4Runtimeサーバー（Stratum）によってPacketInメッセージのメタデータフィールドを
// 設定するために使用されます。ここでは、パケットが受信された元の入力ポートを
// 運ぶために使用します。
@controller_header("packet_in")
header cpu_in_header_t {
    port_num_t  ingress_port;
    bit<7>      _pad;
}

// パケットアウトヘッダー。CPU_PORTから受信したパケットに前置されます。
// このヘッダーのフィールドは、P4Runtime PacketOutメタデータフィールドに基づいて
// P4Runtimeサーバーによって設定されます。ここでは、このパケットアウトが
// どのポートで送信されるべきかをP4パイプラインに通知するために使用します。
@controller_header("packet_out")
header cpu_out_header_t {
    port_num_t  egress_port;
    bit<7>      _pad;
}

struct parsed_headers_t {
    cpu_out_header_t cpu_out;
    cpu_in_header_t cpu_in;
    ethernet_t ethernet;
    ipv4_t ipv4;
    ipv6_t ipv6;
    srv6h_t srv6h;
    srv6_list_t[SRV6_MAX_HOPS] srv6_list;
    tcp_t tcp;
    udp_t udp;
    icmp_t icmp;
    icmpv6_t icmpv6;
    ndp_t ndp;
}

struct local_metadata_t {
    l4_port_t   l4_src_port;
    l4_port_t   l4_dst_port;
    bool        is_multicast;
    ipv6_addr_t next_srv6_sid;
    bit<8>      ip_proto;
    bit<8>      icmp_type;
}


//------------------------------------------------------------------------------
// INGRESS PIPELINE
//------------------------------------------------------------------------------

parser ParserImpl (packet_in packet,
                   out parsed_headers_t hdr,
                   inout local_metadata_t local_metadata,
                   inout standard_metadata_t standard_metadata)
{
    state start {
        transition select(standard_metadata.ingress_port) {
            CPU_PORT: parse_packet_out;
            default: parse_ethernet;
        }
    }

    state parse_packet_out {
        packet.extract(hdr.cpu_out);
        transition parse_ethernet;
    }

    state parse_ethernet {
        packet.extract(hdr.ethernet);
        transition select(hdr.ethernet.ether_type){
            ETHERTYPE_IPV4: parse_ipv4;
            ETHERTYPE_IPV6: parse_ipv6;
            default: accept;
        }
    }

    state parse_ipv4 {
        packet.extract(hdr.ipv4);
        local_metadata.ip_proto = hdr.ipv4.protocol;
        transition select(hdr.ipv4.protocol) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMP: parse_icmp;
            default: accept;
        }
    }

    state parse_ipv6 {
        packet.extract(hdr.ipv6);
        local_metadata.ip_proto = hdr.ipv6.next_hdr;
        transition select(hdr.ipv6.next_hdr) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMPV6: parse_icmpv6;
            IP_PROTO_SRV6: parse_srv6;
            default: accept;
        }
    }

    state parse_tcp {
        packet.extract(hdr.tcp);
        local_metadata.l4_src_port = hdr.tcp.src_port;
        local_metadata.l4_dst_port = hdr.tcp.dst_port;
        transition accept;
    }

    state parse_udp {
        packet.extract(hdr.udp);
        local_metadata.l4_src_port = hdr.udp.src_port;
        local_metadata.l4_dst_port = hdr.udp.dst_port;
        transition accept;
    }

    state parse_icmp {
        packet.extract(hdr.icmp);
        local_metadata.icmp_type = hdr.icmp.type;
        transition accept;
    }

    state parse_icmpv6 {
        packet.extract(hdr.icmpv6);
        local_metadata.icmp_type = hdr.icmpv6.type;
        transition select(hdr.icmpv6.type) {
            ICMP6_TYPE_NS: parse_ndp;
            ICMP6_TYPE_NA: parse_ndp;
            default: accept;
        }
    }

    state parse_ndp {
        packet.extract(hdr.ndp);
        transition accept;
    }

    state parse_srv6 {
        packet.extract(hdr.srv6h);
        transition parse_srv6_list;
    }

    state parse_srv6_list {
        packet.extract(hdr.srv6_list.next);
        bool next_segment = (bit<32>)hdr.srv6h.segment_left - 1 == (bit<32>)hdr.srv6_list.lastIndex;
        transition select(next_segment) {
            true: mark_current_srv6;
            default: check_last_srv6;
        }
    }

    state mark_current_srv6 {
        local_metadata.next_srv6_sid = hdr.srv6_list.last.segment_id;
        transition check_last_srv6;
    }

    state check_last_srv6 {
        // bit<8>とint<32>は直接キャストできないため、比較のために
        // bit<32>を共通の中間型として使用
        bool last_segment = (bit<32>)hdr.srv6h.last_entry == (bit<32>)hdr.srv6_list.lastIndex;
        transition select(last_segment) {
           true: parse_srv6_next_hdr;
           false: parse_srv6_list;
        }
    }

    state parse_srv6_next_hdr {
        transition select(hdr.srv6h.next_hdr) {
            IP_PROTO_TCP: parse_tcp;
            IP_PROTO_UDP: parse_udp;
            IP_PROTO_ICMPV6: parse_icmpv6;
            default: accept;
        }
    }
}


control VerifyChecksumImpl(inout parsed_headers_t hdr,
                           inout local_metadata_t meta)
{
    // ここでは使用されていません。すべてのパケットが有効なチェックサムを持つと仮定し、
    // そうでない場合は、エンドホストにエラーを検出させます。
    apply { /* EMPTY */ }
}


control IngressPipeImpl (inout parsed_headers_t    hdr,
                         inout local_metadata_t    local_metadata,
                         inout standard_metadata_t standard_metadata) {

    // 多くのテーブルで共有されるドロップアクション。
    action drop() {
        mark_to_drop(standard_metadata);
    }


    // *** L2ブリッジング
    //
    // ここでは、イーサネット宛先アドレスに基づいてパケットを転送するテーブルを定義します。
    // サポートする必要があるL2エントリには2つのタイプがあります：
    //
    // 1. ユニキャストエントリ：新しいホストの場所（ポート）が学習されたときに
    //    コントロールプレーンによって入力されます。
    // 2. ブロードキャスト/マルチキャストエントリ：NDP Neighbor Solicitation（NS）
    //    メッセージをすべてのホスト向けポートに複製するために使用されます。
    //
    // （2）について、IPv4のARPメッセージがイーサネット宛先アドレスFF:FF:FF:FF:FF:FFに
    // ブロードキャストされるのとは異なり、NDPメッセージはRFC2464で指定された特別な
    // イーサネットアドレスに送信されます。これらのアドレスは33:33で始まり、
    // 最後の4オクテットはIPv6宛先マルチキャストアドレスの最後の4オクテットです。
    // RFC2464の詳細を掘り下げることなく、このようなIPv6ブロードキャスト/マルチキャスト
    // パケットにマッチする最も直接的な方法は、33:33:**:**:**:**でテルナリーマッチを使用することです。
    // ここで*は「気にしない」を意味します。
    //
    // この理由から、我々のソリューションでは2つのテーブルを定義しています。
    // 1つは正確なマッチング（スイッチASICメモリでスケールしやすい）で、
    // もう1つはテルナリーマッチング（より高価なTCAMメモリが必要、通常ははるかに小さい）を使用します。

    // --- l2_exact_table（ユニキャストエントリ用） --------------------------------

    action set_egress_port(port_num_t port_num) {
        standard_metadata.egress_spec = port_num;
    }

    table l2_exact_table {
        key = {
            hdr.ethernet.dst_addr: exact;
        }
        actions = {
            set_egress_port;
            @defaultonly drop;
        }
        const default_action = drop;
        // @nameアノテーションは、このテーブルカウンターに名前を提供するためにここで使用されます。
        // これは、コンパイラーが対応するP4Infoエンティティを生成するために必要です。
        @name("l2_exact_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    // --- l2_ternary_table（ブロードキャスト/マルチキャストエントリ用） ------------------

    action set_multicast_group(mcast_group_id_t gid) {
        // gidは、イングレスパイプラインの直後にあるTraffic Manager内の
        // Packet Replication Engine（PRE）によって使用され、
        // コントロールプレーンがP4Runtime MulticastGroupEntryメッセージによって
        // 指定した複数の出力ポートにパケットを複製します。
        standard_metadata.mcast_grp = gid;
        local_metadata.is_multicast = true;
    }

    table l2_ternary_table {
        key = {
            hdr.ethernet.dst_addr: ternary;
        }
        actions = {
            set_multicast_group;
            @defaultonly drop;
        }
        const default_action = drop;
        @name("l2_ternary_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }


    // *** TODO EXERCISE 5（IPv6ルーティング）
    //
    // 1. スイッチのMACアドレスを解決するためのNDPメッセージを処理するテーブルを作成します。
    //    このテーブルは以下を行う必要があります：
    //    - hdr.ndp.target_ipv6_addrでマッチ（正確なマッチ）
    //    - アクション「ndp_ns_to_na」を提供（snippets.p4を参照）
    //    - default_actionは「NoAction」である必要があります
    //
    // 2. IPv6ルーティングを処理するテーブルを作成します。L2マイステーションテーブルを作成します
    //    （イーサネット宛先アドレスがスイッチアドレスの場合にヒット）。
    //    このテーブルはパケットに対して何も行うべきではありません（つまり、NoAction）が、
    //    下のコントロールブロックは結果（table.hit）を使用してパケットの処理方法を決定する必要があります。
    //
    // 3. IPv6ルーティング用のテーブルを作成します。アクションセレクターを使用して、
    //    パケットヘッダーフィールド（IPv6送信元/宛先アドレスとフローラベル）のハッシュに
    //    従って次のホップMACアドレスを選択する必要があります。
    //    snippets.p4でアクションセレクターとそれを使用するテーブルの例を参照してください。
    //
    // テーブルには任意の名前を付けることができます。この演習の他の場所で
    // 名前を入力する必要があります。


    // *** TODO EXERCISE 6（SRV6）
    //
    // SRV6ロジックを提供するテーブルを実装します。


    // *** ACL
    //
    // 以前の転送決定をオーバーライドする方法を提供します。例えば、
    // パケットをクローン/CPUに送信する、またはドロップすることを要求します。
    //
    // このテーブルを使用してすべてのNDPパケットをコントロールプレーンにクローンし、
    // ホスト発見を可能にします。新しいホストの場所が発見されたとき、
    // コントローラーは対応するブリッジングとルーティングエントリで
    // L2とL3テーブルを更新することが期待されます。

    action send_to_cpu() {
        standard_metadata.egress_spec = CPU_PORT;
    }

    action clone_to_cpu() {
        // クローニングは、v1model固有のプリミティブを使用して実現されます。ここでは
        // クローン操作のタイプ（イングレスからエグレスパイプライン）、
        // クローンセッションID（CPUのもの）、およびクローンされたパケットレプリカに
        // 保持したいメタデータフィールドを設定します。
        clone3(CloneType.I2E, CPU_CLONE_SESSION_ID, { standard_metadata.ingress_port });
    }

    table acl_table {
        key = {
            standard_metadata.ingress_port: ternary;
            hdr.ethernet.dst_addr:          ternary;
            hdr.ethernet.src_addr:          ternary;
            hdr.ethernet.ether_type:        ternary;
            local_metadata.ip_proto:        ternary;
            local_metadata.icmp_type:       ternary;
            local_metadata.l4_src_port:     ternary;
            local_metadata.l4_dst_port:     ternary;
        }
        actions = {
            send_to_cpu;
            clone_to_cpu;
            drop;
        }
        @name("acl_table_counter")
        counters = direct_counter(CounterType.packets_and_bytes);
    }

    apply {

        if (hdr.cpu_out.isValid()) {
            // *** TODO EXERCISE 4
            // これがコントローラーからのパケットアウトの場合のロジックを実装します：
            // 1. パケットの出力ポートをcpu_outヘッダーで見つかったものに設定
            // 2. cpu_outヘッダーを削除（無効に設定）
            // 3. ここでパイプラインを終了（他のテーブルを通過する必要はありません）
        }

        bool do_l3_l2 = true;

        if (hdr.icmpv6.isValid() && hdr.icmpv6.type == ICMP6_TYPE_NS) {
            // *** TODO EXERCISE 5
            // スイッチのMACアドレスを解決するためのNDPメッセージを処理するロジックを挿入します。
            // 前に作成したNDP応答テーブルを適用する必要があります。
            // これがNDP NSパケットの場合、つまり、マッチするエントリが見つかった場合、
            // 「ndp_ns_to_na」アクションが既に出力ポートを設定しているため、
            // L3とL2テーブルをスキップするために「do_l3_l2」フラグをクリアします。
        }

        if (do_l3_l2) {

            // *** TODO EXERCISE 5
            // マイステーションテーブルにマッチし、ヒット時にルーティングテーブルに
            // マッチするロジックを挿入します。ホップリミットが0に達した場合に
            // パケットをドロップする条件も追加する必要があります。

            // *** TODO EXERCISE 6
            // SRv6マイSIDとトランジットテーブルにマッチするロジック、および
            // PSP動作を実行するロジックを挿入します。ヒント：このロジックは
            // スイッチのマイステーションテーブルをチェックすることと
            // ルーティングテーブルを適用することの間のどこかに属します。

            // L2ブリッジングロジック。まず正確なテーブルを適用...
            if (!l2_exact_table.apply().hit) {
                // ...エントリが見つからない場合、これがマルチキャスト/ブロードキャスト
                // NDP NSパケットの場合に備えて、テルナリーを適用します。
                l2_ternary_table.apply();
            }
        }

        // 最後に、ACLテーブルを適用します。
        acl_table.apply();
    }
}


control EgressPipeImpl (inout parsed_headers_t hdr,
                        inout local_metadata_t local_metadata,
                        inout standard_metadata_t standard_metadata) {
    apply {

        if (standard_metadata.egress_port == CPU_PORT) {
            // *** TODO EXERCISE 4
            // パケットがCPUポートに転送される場合のロジックを実装します。
            // 例えば、イングレスでACLテーブルにマッチしてsend/clone_to_cpuアクションが
            // 実行された場合...
            // 1. cpu_inヘッダーを有効に設定
            // 2. cpu_in.ingress_portフィールドを元のパケットの
            //    入力ポート（standard_metadata.ingress_port）に設定します。
        }

        // これがマルチキャストパケット（l2_ternary_tableによって設定されたフラグ）の場合、
        // パケットが受信されたのと同じポートでパケットを複製しないようにします。
        // これは、入力ポートでNDPリクエストをブロードキャストすることを避けるのに役立ちます。
        if (local_metadata.is_multicast == true &&
              standard_metadata.ingress_port == standard_metadata.egress_port) {
            mark_to_drop(standard_metadata);
        }
    }
}


control ComputeChecksumImpl(inout parsed_headers_t hdr,
                            inout local_metadata_t local_metadata)
{
    apply {
        // 以下は、イングレスパイプラインのndp応答テーブルによって生成された
        // NDP NAパケットのICMPv6チェックサムを更新するために使用されます。
        // この関数は、NDPヘッダーが存在する場合にのみ実行されます。
        update_checksum(hdr.ndp.isValid(),
            {
                hdr.ipv6.src_addr,
                hdr.ipv6.dst_addr,
                hdr.ipv6.payload_len,
                8w0,
                hdr.ipv6.next_hdr,
                hdr.icmpv6.type,
                hdr.icmpv6.code,
                hdr.ndp.flags,
                hdr.ndp.target_ipv6_addr,
                hdr.ndp.type,
                hdr.ndp.length,
                hdr.ndp.target_mac_addr
            },
            hdr.icmpv6.checksum,
            HashAlgorithm.csum16
        );
    }
}


control DeparserImpl(packet_out packet, in parsed_headers_t hdr) {
    apply {
        packet.emit(hdr.cpu_in);
        packet.emit(hdr.ethernet);
        packet.emit(hdr.ipv4);
        packet.emit(hdr.ipv6);
        packet.emit(hdr.srv6h);
        packet.emit(hdr.srv6_list);
        packet.emit(hdr.tcp);
        packet.emit(hdr.udp);
        packet.emit(hdr.icmp);
        packet.emit(hdr.icmpv6);
        packet.emit(hdr.ndp);
    }
}


V1Switch(
    ParserImpl(),
    VerifyChecksumImpl(),
    IngressPipeImpl(),
    EgressPipeImpl(),
    ComputeChecksumImpl(),
    DeparserImpl()
) main;
