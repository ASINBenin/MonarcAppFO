# Routes statiques Traefik — pour les FO sur d'autres machines

Ce dossier est surveillé en direct par Traefik (`--providers.file.watch=true`).
Aujourd'hui il est vide : un seul FO, sur cette même machine, découvert automatiquement
via les labels Docker (`docker-compose.prod.yml`).

**Le jour où un 2ᵉ Front Office tourne sur une autre VM** (même modèle que "Client 3"
sur son propre serveur dans le schéma officiel), pas besoin de toucher à Traefik ni de
le redémarrer : dépose un fichier `.yml` ici, sur ce modèle (à adapter) :

```yaml
# fo-client3.yml
http:
  routers:
    monarcfo-client3:
      rule: "Host(`client3.tonorganisation.lu`)"
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      service: monarcfo-client3

  services:
    monarcfo-client3:
      loadBalancer:
        servers:
          - url: "http://<IP-de-la-VM-du-client3>:80"
```

Traefik détecte le nouveau fichier automatiquement (quelques secondes), sans interruption
de service pour les routes déjà en place.
