# Zapisi odločitev

Ključne odločitve, kratko: kaj sem izbral, zakaj in kaj sem zavrnil. Zapisujem jih sproti, ko jih sprejmem.

| #                                                | Odločitev                                |
| ------------------------------------------------ | ---------------------------------------- |
| [1](#1-go-za-storitev)                           | Go za storitev                           |
| [2](#2-terraform-namesto-cdk)                    | Terraform namesto CDK                    |
| [3](#3-ecs-fargate)                              | ECS Fargate                              |
| [4](#4-build-enkrat-promocija-po-digestu)        | Build enkrat, promocija po digestu       |
| [5](#5-github-oidc-namesto-aws-ključev)          | GitHub OIDC namesto AWS ključev          |
| [6](#6-public-subnets-brez-nat)                  | Public subnets brez NAT                  |
| [7](#7-oblika-odgovora)                          | Oblika odgovora                          |
| [8](#8-struktura-terraforma-in-state)            | Struktura Terraforma in state            |
| [9](#9-javen-dostop-brez-avtentikacije-in-https) | Javen dostop brez avtentikacije in HTTPS |

## 1. Go za storitev

**Odločitev:** storitev napišem v Go, samo s standardno knjižnico.
**Zakaj:** storitev vrne le majhen JSON, bistvo naloge sta pipeline in infrastruktura. Go da statičen binary, zelo majhen image, hitre builde in nobenih zunanjih dependencies, ki bi jih bilo treba pinnati. Routing iz Go 1.22+ (`GET /{accountId}/data`) zadošča brez frameworka.

## 2. Terraform namesto CDK

**Odločitev:** vso infrastrukturo opišem s Terraformom.
**Zakaj:** `terraform fmt` in `validate` delujeta offline in brez AWS accounta, kar je pri meni odločilno. Za majhen nabor resourcov zadošča deklarativen jezik, plan/apply pa da pregleden diff v pipeline-u.
**Posledica:** state moram upravljati izrecno (glej 8). Isto zasnovo bi bilo mogoče izraziti tudi v CDK.

## 3. ECS Fargate

**Odločitev:** storitev teče na ECS Fargate za Application Load Balancerjem, 2 taska v 2 availability zonah.
**Zakaj:** stateless container ne potrebuje strežnikov za patchanje. ECS ima rolling deploy in deployment circuit breaker, ki samodejno naredi rollback neuspelega deploya.
**Posledica:** več Terraforma in stalen strošek (ALB + 2 taska). Pri pravem deployu stack po uporabi odstranim.

## 4. Build enkrat, promocija po digestu

**Odločitev:** job `build` image zgradi enkrat in ga naloži kot artifact. `test` in `scan` preverita isti artifact, CD pa ga pushne v ECR in deploya po digestu (`sha256:...`).
**Zakaj:** naloga zahteva ločena koraka builda in testiranja. Če bi vsak korak image gradil znova, bi se testirano lahko razlikovalo od deployanega. Digest določa natanko en image, tage pa je mogoče premakniti.
**Posledica:** pull requesti ne potrebujejo AWS dostopa. Artifact je treba prenesti iz CI v CD za isti commit. ECR tagi so immutable (commit SHA), zato je digest sledljiv.

## 5. GitHub OIDC namesto AWS ključev

**Odločitev:** GitHub Actions se v AWS prijavi z OIDC in prevzame IAM role. Trust policy role-a omejim na ta repozitorij in environment `production`.
**Zakaj:** shranjeni ključi so dolgoživi, lahko uidejo in jih je treba rotirati. OIDC token je kratkotrajen, v GitHubu ni nobene AWS skrivnosti, forki pa role-a ne morejo prevzeti.
**Zavrnjeno:** access keys IAM userja v GitHub secrets (dolgoživi) in self-hosted runnerji z instance profili (dodatno upravljanje).
**Posledica:** OIDC provider in role enkrat ročno ustvari `infra/bootstrap`. Trust policy mora biti ozka, sicer izgubi smisel.

## 6. Public subnets brez NAT

**Odločitev:** taski tečejo v public subnets. Security group sprejema dohodni promet samo iz security groupa load balancerja.
**Zakaj:** v private subnets bi za pull image-a in pošiljanje logov potreboval NAT gateway ali VPC endpoints, ki imajo stalen strošek, velik v primerjavi z majhno storitvijo.
**Zavrnjeno:** private subnets z NAT (draga in odveč) ter z VPC endpoints (več resourcov in stroškov).
**Posledica:** taski imajo javne IP-je, a se nanje neposredno ni mogoče povezati. Je kompromis za MVP; prehod na private subnets spremeni le network modul (SPEC, razdelek 13).

## 7. Oblika odgovora

Naloga ne pove, ali je `timestamp` število ali niz, in ne omeji `accountId`, ki ga storitev vrne nazaj.

**Odločitev:**

- `timestamp` je JSON število: Unix time v sekundah. Je definiran glede na UTC, zato ni dvoumnosti glede timezone-a, naloga pa ga prikazuje brez narekovajev.
- `accountId` mora ustrezati `^[A-Za-z0-9_-]{1,64}$`, sicer vrnem 400. Tako ne vračam poljubnega inputa.
- `data` je 16 naključnih bajtov iz kriptografskega vira, zapisanih v hex.

**Zavrnjeno:** ISO 8601 niz (client ga mora parsati, naloga ne kaže narekovajev), milisekunde (lahko se zamenjajo s sekundami), sprejem vsakega `accountId` (nepotrebno tveganje).
**Posledica:** obliko je mogoče natančno testirati s fiksnim clockom. Če pravi ID-ji potrebujejo druge znake, moram pattern razširiti.

## 8. Struktura Terraforma in state

**Odločitev:** dva ločena root modula.

- `infra/bootstrap`: poženem ga enkrat, ročno. Ustvari ECR repozitorij, S3 bucket za state, GitHub OIDC provider in role za deploy. State je lokalen. V kodi je zaenkrat samo ECR, ostalo je opisano.
- `infra/service`: poganja ga pipeline. State je v S3 z native lockingom (`use_lockfile`), brez DynamoDB.

Verzije Terraforma in providerjev pinnam, `.terraform.lock.hcl` je v repozitoriju.

**Zakaj:** pipeline ne more ustvariti state-a in role-a, od katerih je sam odvisen. Z ločitvijo role pipeline-a omejim na resource aplikacije, tako da ne more spreminjati same sebe. ECR repozitorij je v bootstrapu, ker ga mora pipeline imeti, preden pushne prvi image, in ker brisanje service-a ne sme pobrisati image-ov.
**Zavrnjeno:** en modul za vse (pipeline bi upravljal lastne pravice), DynamoDB za locking (odveč) in Terraform Cloud (zunanja storitev).
**Posledica:** en ročni korak, ki ga opišem v README. State bootstrapa moram varno hraniti. Brez AWS accounta oba modula preverim samo s `terraform fmt` in `validate` (`init -backend=false`).

## 9. Javen dostop brez avtentikacije in HTTPS

**Odločitev:** ALB sprejema promet z vsega interneta (`0.0.0.0/0`) na portu 80. Service nima avtentikacije, promet ni šifriran, pred ALB ni WAF.
**Zakaj:** naloga zahteva javno dostopen HTTP service z eno GET potjo. Odgovor ne vsebuje občutljivih podatkov: naključen niz, timestamp in `accountId`, ki ga validiram (odločitev 7). HTTPS zahteva ACM certifikat in domeno, ki je nimam. Izpostavljenost zmanjšam s security groupi: na ALB je odprt samo port 80, taski pa sprejemajo promet samo iz security groupa ALB.
**Zavrnjeno:** omejitev dostopa na moj IP (service je namenjen odjemalcem, ne samo meni; za demo deploy bi to lahko dodal), avtentikacija z API keyem ali JWT (naloga je ne zahteva in bi povečala obseg), WAF (dodaten strošek in obseg).
**Posledica:** vsak, ki pozna DNS ime ALB, lahko kliče service. Tveganje je predvsem strošek ob veliki količini zahtevkov in nešifriran promet. Za pravi production bi dodal HTTPS (ACM + Route 53), WAF z rate limitom in po potrebi avtentikacijo ali omejitev po IP. Vse to je v razdelku 13 specifikacije.
