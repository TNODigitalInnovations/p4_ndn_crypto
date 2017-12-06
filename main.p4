#define ETHERTYPE_IPV4 0x0800
#define IPPROTO_UDP 17

header_type ethernet_t {
  fields {
    dstAddr   : 48;
    srcAddr   : 48;
    etherType : 16;
  }
}

header_type ipv4_t {
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}

header_type udp_t {
    fields {
        srcPort  : 16;
        dstPort  : 16;
        len      : 16;
        checksum : 16;
    }
}


parser start {
  return parse_ethernet;
}

header ethernet_t ethernet;

parser parse_ethernet {
  extract(ethernet);
  return select(latest.etherType) {
    ETHERTYPE_IPV4:    parse_ipv4;
    default:  ingress;
  }
}

header ipv4_t ipv4;

field_list ipv4_checksum_list {
        ipv4.version;
        ipv4.ihl;
        ipv4.diffserv;
        ipv4.totalLen;
        ipv4.identification;
        ipv4.flags;
        ipv4.fragOffset;
        ipv4.ttl;
        ipv4.protocol;
        ipv4.srcAddr;
        ipv4.dstAddr;
}

field_list_calculation ipv4_checksum {
    input {
        ipv4_checksum_list;
    }
    algorithm : csum16;
    output_width : 16;
}


calculated_field ipv4.hdrChecksum  {

    verify ipv4_checksum;
    update ipv4_checksum;

}

parser parse_ipv4 {
  extract(ipv4);
  return select(latest.protocol) {
    IPPROTO_UDP:     parse_udp;
    default:  ingress;
  }
}


header udp_t udp;

parser parse_udp {
  extract(udp);
  return ingress;
}


field_list udp_checksum_list {
    ipv4.srcAddr;
    ipv4.dstAddr;
    8'0;
    ipv4.protocol;
    udp.len;
    udp.srcPort;
    udp.dstPort;
    udp.len;
    udp.checksum;
    payload;
}

field_list_calculation udp_checksum {
    input {
        udp_checksum_list;
    }
    algorithm : csum16;
    output_width : 16;
}

calculated_field udp.checksum {
    update udp_checksum;
}

primitive_action payload_scan();

action act_drop(){
  drop();
}


action act_modify_and_send(port){
  payload_scan();
  modify_field(udp.checksum, udp.len);
  modify_field(standard_metadata.egress_spec, port);
}

action act_do_forward(espec) {
   modify_field(standard_metadata.egress_spec, espec);
}

table tbl_forward_udp {
  actions {
    act_modify_and_send;
  }
}

table tbl_drop {
    reads {
        standard_metadata.ingress_port : exact;
    }
    actions {
		act_drop;
    }
}


control ingress {
   if(valid(udp)){
        apply(tbl_forward_udp);
   } else {
       apply(tbl_drop);
   }
}

control egress {
}