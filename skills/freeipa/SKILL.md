---
name: freeipa
description: >
  FreeIPA / Red Hat IdM patterns — certificates, Kerberos, LDAP integration,
  DNS and client enrolment. Use when working with an IPA server or its clients:
  requesting certificates, mapping LDAP for an application, managing DNS zones
  and principals, enrolling hosts, or debugging certmonger. Trigger on phrases
  like "ipa cert-request", "certmonger", "keytab", "kinit", "ipaUniqueID",
  "LDAPS", "enrol a host", "service principal".
license: MIT
compatibility: opencode
metadata:
  type: identity
  domain: infrastructure
---

# FreeIPA

FreeIPA bundles DNS, a CA, Kerberos, LDAP and user management. Almost every
non-obvious behaviour below comes from one design principle:

**The CA only issues certificates for names that have a principal.**

That single rule explains most failures. Remember it and the rest follows.

---

## Certificates

### The principal gate

`ipa cert-request` rejects a CSR whose subject does not map to a known
principal:

```
ERROR: The service principal for subject alt name ldap.example.com
       in certificate request does not exist
```

Each name in the certificate — subject **and** every SAN — needs a principal.
Create them first:

```bash
ipa host-add name.example.com --force        # → host/name.example.com
ipa service-add HTTP/name.example.com        # → HTTP/name.example.com
```

`host-add` refuses `--ip-address` when DNS already owns that address; the host
object only needs to exist as a principal container, so omit the address.

For an **alias** name that a host will serve (e.g. `sso.example.com` on
`sso01`), the host also needs permission to request for it:

```bash
ipa service-add-host HTTP/alias.example.com --hosts=realhost.example.com
```

### certmonger

`ipa-getcert` / `getcert` manage tracked certificates with automatic renewal.
`getcert list` shows status; `status: MONITORING` and `auto-renew: yes` are
healthy. `getcert resubmit -i <id>` re-issues.

**Limitation: one SAN.** `-D DNSNAME` *overrides* the requested DNS name rather
than accumulating, so certmonger cannot request a multi-SAN certificate. For a
certificate covering more than one name, use the CSR route:

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout k.key -out r.csr \
  -subj "/CN=host.example.com" \
  -addext "subjectAltName=DNS:host.example.com,DNS:alias.example.com"
ipa cert-request --principal=HTTP/host.example.com --certificate-out=c.crt r.csr
```

Two traps in that command: `-subj` swallows `,O=...` into the CN if you are not
careful with the DN, and a stale CSR will be re-submitted silently — delete it
before regenerating.

The post-save command (`-C`) is parsed by `g_spawn_command_line_async`, which
does **not** invoke a shell — `a && b` is passed as literal arguments. Wrap in
`sh -c '…'`. Even then, it may not fire; a systemd path unit watching the
certmonger store is a more reliable delivery mechanism.

### Installing into a service

certmonger writes PEM by default, but some services (389-ds) use an NSS
database. Replacing a cert there means the key must match — bundle key and cert
into PKCS#12 and import over the nickname, then restart the service.

## LDAP integration

FreeIPA is 389-ds underneath. The mapping that matters when pointing an
application at it:

| App expects | FreeIPA value |
|---|---|
| stable user id | **`ipaUniqueID`** — *not* `entryUUID` or `objectGUID` |
| login attribute | `uid` |
| RDN attribute | `uid` |
| user base | `cn=users,cn=accounts,dc=example,dc=com` |
| group base | `cn=groups,cn=accounts,dc=example,dc=com` |
| object classes | `posixAccount, inetOrgPerson, organizationalPerson, top` |
| directory vendor | `rhds` (Red Hat Directory Server profile) |

Get `ipaUniqueID` wrong and every login looks like a brand-new user.

Use **`editMode: READ_ONLY`** in anything that federates users — FreeIPA must
stay the only writable user store. Set `trustEmail: false`: an LDAP `mail`
attribute is not proof of address ownership.

### Service accounts vs people

Accounts created to *bind* are not users. Filter who counts as a real user with
group membership, and never expose bind accounts in an application's user list.

### Authentication

`kinit` obtains a TGT; subsequent Kerberos calls work without the password.
`ipa` and `ldapsearch -Y GSSAPI` both work with a TGT — much better than
passing bind credentials in scripts. Service accounts use simple binds with
`uid=<name>,cn=users,cn=accounts,<base>`.

`kinit` output is a credential cache; `kdestroy` clears it. Tickets cannot be
revoked before expiry — account disabling does not affect a live TGT.

## DNS

`ipa dnsrecord-add` / the `ipadnsrecord` module manage a zone declaratively.
Reverse records live in `in-addr.arpa` zones and the owner name is the reversed
octets for a /24.

**Avoid `create_reverse`** — it writes a *relative* PTR target and produces
values like `host.example.com.<reverse-zone>.`. Manage PTRs explicitly with an
absolute target (trailing dot).

Deleting records is not automatic when they are removed from declared state —
prune them explicitly with `state: absent`.

## Client enrolment

`ipa-client-install` gets a host keytab and configures SSSD. Differences that
bite:

| | EL | Debian |
|---|---|---|
| package | `ipa-client` | `freeipa-client` |
| PAM | `authselect` | `pam-auth-update` |
| home dirs | `oddjob-mkhomedir` | `pam_mkhomedir` — enable it or nothing happens |
| sudo from IPA | works out of the box | `sudoers: files sss` in nsswitch |
| time service | `chronyd` | `chrony` |

Enrolment makes the host depend on the IPA server for login. Keep a local
fallback account. Discovery uses DNS SRV records, so the host must resolve the
domain before enrolment.

## Debugging

```bash
getcert list                      # tracked certificates and status
klist                             # cached tickets
kvno HTTP/host.example.com        # can this principal get a service ticket?
openssl s_client -connect host:636 | openssl x509 -noout -subject -issuer
ipa user-show name                # needs a TGT first
```

An error code 49 from LDAP is **invalid credentials**, not TLS — TLS failures
look different. Certificate errors naming a missing principal mean the name is
not claimable yet.
