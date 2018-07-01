# Digital Ocean Tag for all server instances
resource "digitalocean_tag" "ipfs-live-streaming" {
  name = "ipfs-live-streaming"
}

# Domain name managed by Digital Ocean
resource "digitalocean_domain" "ipfs-live-streaming" {
  name       = "${file(var.domain_name)}"
  ip_address = "${digitalocean_droplet.ipfs-server.ipv4_address}"
}

# RTMP server Droplet
resource "digitalocean_droplet" "rtmp-server" {
  image              = "debian-9-x64"
  name               = "rtmp-server"
  region             = "tor1"
  size               = "1gb"
  tags               = ["${digitalocean_tag.ipfs-live-streaming.id}"]
  private_networking = true
  ipv6               = true
  monitoring         = true
  ssh_keys           = ["${file(var.ssh_fingerprint)}"]
  connection {
    user             = "root"
    type             = "ssh"
    private_key      = "${file(var.pvt_key)}"
    timeout          = "2m"
  }
  provisioner "file" {
    source           = "rtmp-server"
    destination      = "/tmp"
  }
  provisioner "remote-exec" {
    inline           = [
      "chmod +x /tmp/rtmp-server/bootstrap.sh",
      "/tmp/rtmp-server/bootstrap.sh",
    ]
  }
  provisioner "local-exec" {
    command          = "scp -B -o 'StrictHostKeyChecking no' -i ${var.pvt_key} root@${digitalocean_droplet.rtmp-server.ipv4_address}:/root/client-keys/* .keys/"
  }
}

# DNS records for RTMP server
resource "digitalocean_record" "rtmp-server" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "rtmp-server"
  value  = "${digitalocean_droplet.rtmp-server.ipv4_address}"
  ttl    = "600"
}
resource "digitalocean_record" "rtmp-server-private" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "private.rtmp-server"
  value  = "${digitalocean_droplet.rtmp-server.ipv4_address_private}"
  ttl    = "600"
}
resource "digitalocean_record" "rtmp-server-v6" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "AAAA"
  name   = "v6.rtmp-server"
  value  = "${digitalocean_droplet.rtmp-server.ipv6_address}"
  ttl    = "600"
}

# DNS records for authenticated RTMP publishing
resource "digitalocean_record" "publish-openvpn" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "openvpn.publish"
  value  = "10.10.10.1"
  ttl    = "600"
}
resource "digitalocean_record" "publish-yggdrasil" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "AAAA"
  name   = "yggdrasil.publish"
  value  = "${file(".keys/rtmp_yggdrasil")}"
  ttl    = "600"
}

# IPFS server Droplet
resource "digitalocean_droplet" "ipfs-server" {
  depends_on         = ["digitalocean_droplet.rtmp-server"]
  image              = "debian-9-x64"
  name               = "ipfs-server"
  region             = "tor1"
  size               = "1gb"
  tags               = ["${digitalocean_tag.ipfs-live-streaming.id}"]
  private_networking = true
  ipv6               = true
  monitoring         = true
  ssh_keys           = ["${file(var.ssh_fingerprint)}"]
  connection {
    user             = "root"
    type             = "ssh"
    private_key      = "${file(var.pvt_key)}"
    timeout          = "2m"
  }
  provisioner "file" {
    source           = "shared/video-player"
    destination      = "/tmp"
  }
  provisioner "file" {
    source           = "ipfs-server"
    destination      = "/tmp"
  }
  provisioner "remote-exec" {
    inline           = [
      "chmod +x /tmp/ipfs-server/bootstrap.sh",
      "chmod +x /tmp/ipfs-server/process-stream.sh",
      "/tmp/ipfs-server/bootstrap.sh ${file(var.domain_name)} ${digitalocean_droplet.rtmp-server.ipv4_address_private} ${var.mirror}",
    ]
  }
  provisioner "local-exec" {
    command          = "scp -B -o 'StrictHostKeyChecking no' -i ${var.pvt_key} root@${digitalocean_droplet.ipfs-server.ipv4_address}:/root/client-keys/* .keys/"
  }
}

# DNS records for IPFS server
resource "digitalocean_record" "ipfs-server" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "ipfs-server"
  value  = "${digitalocean_droplet.ipfs-server.ipv4_address}"
  ttl    = "600"
}
resource "digitalocean_record" "ipfs-server-private" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "private.ipfs-server"
  value  = "${digitalocean_droplet.ipfs-server.ipv4_address_private}"
  ttl    = "600"
}
resource "digitalocean_record" "ipfs-server-v6" {
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "AAAA"
  name   = "v6.ipfs-server"
  value  = "${digitalocean_droplet.ipfs-server.ipv6_address}"
  ttl    = "600"
}

# IPFS mirror Droplet
resource "digitalocean_droplet" "ipfs-mirror" {
  depends_on         = ["digitalocean_droplet.ipfs-server"]
  count              = "${var.mirror}"
  image              = "debian-9-x64"
  name               = "ipfs-mirror"
  region             = "tor1"
  size               = "1gb"
  tags               = ["${digitalocean_tag.ipfs-live-streaming.id}"]
  private_networking = true
  ipv6               = true
  monitoring         = true
  ssh_keys           = ["${file(var.ssh_fingerprint)}"]
  connection {
    user             = "root"
    type             = "ssh"
    private_key      = "${file(var.pvt_key)}"
    timeout          = "2m"
  }
  provisioner "file" {
    source           = "shared/video-player"
    destination      = "/tmp"
  }
  provisioner "file" {
    source           = "ipfs-mirror"
    destination      = "/tmp"
  }
  provisioner "remote-exec" {
    inline           = [
      "chmod +x /tmp/ipfs-mirror/bootstrap.sh",
      "chmod +x /tmp/ipfs-mirror/ipfs-pin.sh",
      "chmod +x /tmp/ipfs-mirror/ipfs-pin-service.sh",
      "/tmp/ipfs-mirror/bootstrap.sh ${count.index} ${file(var.domain_name)} ${file(".keys/ipfs_id")} ${var.mirror}",
    ]
  }
}

# DNS records for IPFS mirror
resource "digitalocean_record" "ipfs-mirror" {
  count  = "${var.mirror}"
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "ipfs-mirror-${count.index}"
  value  = "${element(digitalocean_droplet.ipfs-mirror.*.ipv4_address, count.index)}"
  ttl    = "600"
}
resource "digitalocean_record" "ipfs-mirror-private" {
  count  = "${var.mirror}"
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "A"
  name   = "private.ipfs-mirror-${count.index}"
  value  = "${element(digitalocean_droplet.ipfs-mirror.*.ipv4_address_private, count.index)}"
  ttl    = "600"
}
resource "digitalocean_record" "ipfs-mirror-v6" {
  count  = "${var.mirror}"
  domain = "${digitalocean_domain.ipfs-live-streaming.name}"
  type   = "AAAA"
  name   = "v6.ipfs-mirror-${count.index}"
  value  = "${element(digitalocean_droplet.ipfs-mirror.*.ipv6_address, count.index)}"
  ttl    = "600"
}

# Print summary
output "digital_ocean_droplets" {
  depends_on = ["digitalocean_record.*"]
  value      = [
    "${digitalocean_droplet.rtmp-server.name}:             ${digitalocean_droplet.rtmp-server.status}",
    "${digitalocean_droplet.ipfs-server.name}:             ${digitalocean_droplet.ipfs-server.status}",
    "ipfs-mirror instance(s): ${length(digitalocean_droplet.ipfs-mirror.*.status)}",
    "${digitalocean_droplet.ipfs-mirror.*.status}",
  ]
}
output "dns_records" {
  depends_on = ["digitalocean_record.*"]
  value      = [
    "                  ${digitalocean_domain.ipfs-live-streaming.name} = ${digitalocean_domain.ipfs-live-streaming.ip_address}",
    "      ${digitalocean_record.rtmp-server.fqdn} = ${digitalocean_record.rtmp-server.value}",
    "      ${digitalocean_record.ipfs-server.fqdn} = ${digitalocean_record.ipfs-server.value}",
    "${zipmap(digitalocean_record.ipfs-mirror.*.fqdn, digitalocean_record.ipfs-mirror.*.value)}",
    "      ${digitalocean_record.rtmp-server-private.fqdn} = ${digitalocean_record.rtmp-server-private.value}",
    "      ${digitalocean_record.ipfs-server-private.fqdn} = ${digitalocean_record.ipfs-server-private.value}",
    "${zipmap(digitalocean_record.ipfs-mirror-private.*.fqdn, digitalocean_record.ipfs-mirror-private.*.value)}",
    "      ${digitalocean_record.rtmp-server-v6.fqdn} = ${digitalocean_record.rtmp-server-v6.value}",
    "      ${digitalocean_record.ipfs-server-v6.fqdn} = ${digitalocean_record.ipfs-server-v6.value}",
    "${zipmap(digitalocean_record.ipfs-mirror-v6.*.fqdn, digitalocean_record.ipfs-mirror-v6.*.value)}",
    "     ${digitalocean_record.publish-openvpn.fqdn} = ${digitalocean_record.publish-openvpn.value}",
    "   ${digitalocean_record.publish-yggdrasil.fqdn} = ${digitalocean_record.publish-yggdrasil.value}",
  ]
}
output "ssh_access" {
  depends_on = ["digitalocean_record.*"]
  value      = [
    "rtmp-server: ssh -i .keys/id_rsa root@${digitalocean_record.rtmp-server.fqdn}",
    "ipfs-server: ssh -i .keys/id_rsa root@${digitalocean_record.ipfs-server.fqdn}",
    "ipfs-mirror: ssh -i .keys/id_rsa root@ipfs-mirror-N.${digitalocean_domain.ipfs-live-streaming.name}",
  ]
}
output "private_urls" {
  depends_on = ["digitalocean_record.*"]
  value      = [
    "RTMP publish (.keys/client.conf):    rtmp://10.10.10.1:1935/live",
    "RTMP publish (.keys/yggdrasil.conf): rtmp://[${digitalocean_record.publish-yggdrasil.value}]:1935/live",
  ]
}
output "public_urls" {
  depends_on = ["digitalocean_record.*"]
  value      = [
    "RTMP stream: rtmp://${digitalocean_record.rtmp-server.fqdn}/live",
    "HLS stream:  http://${digitalocean_domain.ipfs-live-streaming.name}:8080/ipns/${file(".keys/ipfs_id")}",
  ]
}