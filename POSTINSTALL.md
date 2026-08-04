## Your Lore server is running

Check it in one command, from any machine with the [`lore` client](https://github.com/EpicGames/lore/releases) installed:

```
lore repository list lores://myapp.example.com:41337
```

An empty list and no error means everything is working: the port is open, the certificate is valid, and the server is ready for your first repository. Cloudron issues and renews that certificate for you, so there is nothing to configure at either end.

**Note the `lores://` scheme, with the `s`.** It is the secure one, and the one this server uses. Plain `lore://` will appear to hang rather than give you an error.

## There is no web interface, by design

Lore is driven entirely by the `lore` client, so this app has no page to visit and the dashboard's **Open** button will show a 404. That is expected, not a fault. Upstream has committed to a web client in 2027.

The health indicator beside this app in your dashboard tells you the server is up.

## Your first repository

```
lore repository create lores://myapp.example.com:41337/my-project
cd my-project
lore dirty .          # tell Lore what changed
lore stage .
lore commit "first import"
lore push
```

The `lore dirty` step is worth remembering: Lore does not scan for changes by itself, so without it a commit will report nothing to do.

## Before you put real work here

**The server currently accepts any client that can reach it.** Lore ships with authentication switched off, and this package does not invent credentials for you.

**For most people the simplest answer is to close the ports.** If your team reaches this server over a VPN or from inside your own network, turn off the TCP and UDP port forwarding for this app in the dashboard. It stays fully usable, and nothing on the public internet can touch it.

If you need it reachable from anywhere, configure JWT authentication instead: edit `/app/data/config/local.toml` through the dashboard file manager, fill in the `[server.auth]` block for your identity provider, and restart the app. This is Lore's own token system rather than Cloudron single sign-on, so your users will not log in through the dashboard.

## Two things worth knowing

**Keep both port numbers the same.** The TCP and UDP ports must match, because clients use one address for both. The dashboard lets you change them independently and will not warn you.

**Your data is backed up normally.** Everything Lore stores lives in the app's data directory, so Cloudron's backups cover it, and a restore brings it all back. Verified, including a restore that rolled the server back cleanly.

---

Full documentation, including the version-bump procedure and notes for administrators, is in the [package repository](https://github.com/OrcVole/lore-cloudron).
