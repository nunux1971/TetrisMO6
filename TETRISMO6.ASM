*****************************************************************
*  PETIT RAPPEL POUR LIRE CE PROGRAMME                          *
*****************************************************************
*  Le 6809 possede :
*   A, B   : 2 accumulateurs de 8 bits (0..255)
*   D      : A et B colles ensemble = 16 bits (A = octet haut)
*   X, Y   : 2 registres d'index 16 bits (des "pointeurs")
*   U, S   : 2 piles 16 bits (S = pile systeme utilisee par JSR/RTS)
*   CC     : les drapeaux (Z=zero, N=negatif, C=retenue, V=debordement)
*   DP     : page directe (non utilisee ici)
*
*  Modes d'adressage rencontres :
*   #10      valeur immediate (le nombre 10 lui-meme)
*   $A7C0    adresse memoire (on lit/ecrit la case $A7C0)
*   ,X       la case pointee par X
*   5,X      la case X+5
*   ,X+      la case pointee par X, puis X = X+1 (++ : X+2)
*   A,X      la case X+A (A est pris comme nombre signe -128..127)
*
*  $xx = hexadecimal. % = binaire. Les etiquettes (noms en debut de
*  ligne) sont des adresses que l'assembleur calcule tout seul.
*
*  Memoire video du MO6 (mode 40 colonnes, 320x200) :
*   $0000-$1F3F : 8000 octets, 40 octets par ligne de pixels.
*   Chaque octet = 8 pixels. Il y a DEUX memoires a la meme adresse :
*    - la "forme"   : 1 bit par pixel (1 = couleur de forme)
*    - la "couleur" : pour ces 8 pixels, 4 bits couleur de forme
*                     (poids fort) + 4 bits couleur de fond.
*   Le bit 0 du registre $A7C0 choisit laquelle on voit a $0000.
*  Un "caractere" de 8x8 = 8 octets espaces de 40 (une ligne ecran
*  de texte = 8 lignes de pixels = 320 octets).
*****************************************************************

*****************************************************************
*  TETRIS - clone de la version Game Boy                        *
*  Thomson MO6 - assembleur 6809E (syntaxe lwasm / c6809)       *
*  Chargement en $7400, lancement : EXEC &H7400                 *
*****************************************************************

PRA     equ     $A7C0           ; registre du PIA systeme, port A
PRB     equ     $A7C1           ; port B : clavier + buzzer
PALD    equ     $A7DA           ; registre de donnees de la palette
PALA    equ     $A7DB           ; registre d'adresse (numero de couleur x2)
GATE    equ     $A7E7           ; registre du "gate array" video

* palette : 0 noir 1 bleu nuit 2 blanc 3 gris clair 4-10 pieces
*           11 brique 12 joint 13 ciel 14 gris fonce 15 sable
CFIELD  equ     $21             ; couleur = 16 x forme + fond ($21 : forme 2, fond 1)
CBRICK  equ     $CB             ; joint sur brique
CTEXT   equ     $03             ; noir sur gris clair (panneaux)
CTITLE  equ     $21             ; blanc sur bleu nuit
CYEL    equ     $51             ; jaune sur bleu nuit
CHELP   equ     $31             ; gris clair sur bleu nuit
CSKY    equ     $0D             ; noir sur ciel
CCLOUD  equ     $2D             ; blanc sur ciel
CTOWER  equ     $ED             ; gris fonce sur ciel
T_PAN   equ     25              ; numero de la tuile "case vide" coloree selon tcol
* Bits de l'octet "keys" : une touche = un bit

K_LEFT  equ     $01             ; fleche gauche
K_RIGHT equ     $02             ; fleche droite
K_DOWN  equ     $04             ; fleche bas
K_ROTA  equ     $08             ; rotation A (haut ou espace)
K_ROTB  equ     $10             ; rotation B (X ou W)
K_DROP  equ     $20             ; chute directe (ENTREE)
K_PAUSE equ     $40             ; pause (P)
K_STOP  equ     $80             ; STOP
* Disposition de l'ecran et reglages du jeu

FLD     equ     15              ; colonne ecran de la 1re colonne du puits (centre)
FX      equ     FLD-3           ; colonne ecran = colonne plateau + FX
PNL     equ     20              ; colonne du panneau score
SPAWN   equ     2*16+6          ; index dans le tableau "board" (ligne*16 + colonne)
DASD    equ     14              ; delai avant repetition gauche/droite (images)
DASR    equ     5               ; vitesse de repetition
SDR     equ     2               ; descente rapide : 1 ligne toutes les 2 images
* Numeros des tuiles du cadre arrondi (voir table "tiles")

T_TL    equ     10              ; coin haut gauche
T_T     equ     11              ; bord haut
T_TR    equ     12              ; coin haut droit
T_L     equ     13              ; bord gauche
T_R     equ     14              ; bord droit
T_BL    equ     15              ; coin bas gauche
T_B     equ     16              ; bord bas
T_BR    equ     17              ; coin bas droit

        org     $7400           ; adresse ou le programme sera range en memoire
        jmp     start           ; 1re instruction : on saute par-dessus les scores
hisA    fcb     0,0,0           ; place fixe : le BASIC lit et ecrit ces 6 octets
hisB    fcb     0,0,0           ; $7406 : meilleur score type B (BCD)

* ===== DEMARRAGE (appele par EXEC &H7400) =====
*----------------------------------------------------------------
start   pshs    cc,a,b,dp,x,y,u  ; sauve tous les registres du BASIC sur la pile
        orcc    #$50            ; masque les interruptions (le BASIC ne tourne plus)
        sts     savesp          ; memorise la pile pour pouvoir y revenir d'ou qu'on soit
        lda     PRA             ; lit le port A...
        ora     #$08            ; ...met le bit 3 a 1 (lignes 0-7 du clavier)...
        sta     PRA             ; ...et le reecrit
        ldx     #gbpal          ; X = adresse de notre palette de 16 couleurs
        ldb     #32             ; 16 couleurs x 2 octets = 32 octets a envoyer
        jsr     setpal          ; JSR = appel de sous-programme (retour par RTS)
        ldd     #$ACE1          ; valeur de depart du generateur aleatoire
        std     seed            ; STD = range D (A et B) en memoire, sur 2 octets
        ldx     #hisA           ; par defaut on affiche le record du type A
        stx     hisptr          ; hisptr pointe vers le record du type choisi
        clr     gtype           ; CLR = met l'octet a 0 : type A
        clr     bheight         ; hauteur des dechets du type B = 0
        clr     msel            ; ligne du menu selectionnee = la 1re
        clr     startlv         ; niveau de depart 0
        lda     #$FF            ; $FF = "pas de piece" (utile pour le tirage)
        sta     piece
        jmp     title           ; JMP = saut sans retour vers l'ecran titre

* ===== RETOUR AU BASIC (touche STOP sur l'ecran titre) =====
* retour au BASIC
quit    lds     savesp          ; remet la pile comme au demarrage
        ldx     #defpal         ; palette d'origine du MO6
        ldb     #32             ; 32 octets
        jsr     setpal
        lda     #$70            ; $70 = blanc sur noir
        jsr     cls             ; efface l'ecran
        clr     PRB             ; coupe le buzzer
        puls    cc,a,b,dp,x,y,u,pc  ; recupere les registres ; PC depile = retour au BASIC

* ----- setpal : envoie B octets de palette depuis X
* X = table, B = nombre d'octets
setpal  clr     PALA            ; on commence a la couleur 0
sp1     lda     ,x+             ; A = octet suivant de la table (X avance de 1)
        sta     PALD            ; envoye au circuit palette (il avance tout seul)
        decb                    ; DECB = B - 1 (met Z a 1 quand B arrive a 0)
        bne     sp1             ; BNE = recommence tant que B n'est pas nul
        rts                     ; RTS = retour a l'appelant

*----------------------------------------------------------------
* synchro trame
* (avec delai de securite ~24 ms si le registre ne bouge pas)
vsync   pshs    x               ; on garde X (PSHS empile, PULS depile)
        ldx     #1500           ; compteur de securite (~24 ms)
vs1     lda     GATE            ; lit le registre video
        bmi     vs1b            ; BMI : bit 7 a 1 -> l'image est en cours d'affichage
        leax    -1,x            ; LEAX -1,X : X = X - 1
        bne     vs1             ; pas encore a 0 ? on continue d'attendre
        puls    x,pc            ; delai depasse : on sort quand meme
vs1b    ldx     #1500           ; compteur de securite pour la 2e attente
vs2     lda     GATE            ; relit le registre
        bpl     vs3             ; BPL : bit 7 a 0 -> debut du retour de trame, c'est parti
        leax    -1,x            ; X = X - 1
        bne     vs2             ; on attend encore
vs3     puls    x,pc            ; PULS ...,PC depile X puis revient (comme RTS)

* attendre B images
waitf   pshs    b               ; B est mis sur la pile et sert de compteur
wf1     bsr     vsync           ; BSR = JSR pour une routine proche
        dec     ,s              ; decremente le compteur directement sur la pile (,S)
        bne     wf1             ; pas fini ? image suivante
        puls    b,pc            ; depile B et revient

* Principe : on ecrit le numero d'une touche (colonne*16 + ligne*2)
* dans PRB, puis on relit PRB : bit 7 = 0 si la touche est enfoncee.
* La table ktab contient des paires (code touche, bit de keys).
*----------------------------------------------------------------
* lecture clavier MO6 -> keys, edge (nouvelles touches)
scan    clra                    ; A va accumuler les bits des touches enfoncees
        ldx     ktab            ; X = table des touches a tester (jeu ou menu)
sc1     ldb     ,x+             ; B = code de la touche
        cmpb    #$FF            ; $FF = fin de table
        beq     sc3             ; BEQ : saute si egal (Z=1)
        stb     PRB             ; selectionne la touche dans la matrice du clavier
        ldb     PRB             ; relit le port : bit 7 = etat de la touche
        bmi     sc2             ; bit 7 a 1 = touche relachee -> on passe
        ora     ,x              ; ORA ,X : ajoute le bit de cette touche dans A
sc2     leax    1,x             ; passe au couple suivant
        bra     sc1             ; BRA = saut inconditionnel
sc3     sta     keys            ; keys = touches enfoncees maintenant
        ldb     prevk           ; B = touches de l'image precedente
        comb                    ; COMB inverse tous les bits : touches qui etaient relachees
        andb    keys            ; ET avec les touches actuelles...
        stb     edge            ; ...= touches qui viennent juste d'etre enfoncees (fronts)
        sta     prevk           ; memorise pour la prochaine fois
        rts

*----------------------------------------------------------------
* effacement ecran : A = couleur
cls     pshs    a               ; garde la couleur voulue
        lda     PRA             ; selectionne la memoire "forme"
        ora     #1              ; bit 0 a 1
        sta     PRA
        ldx     #0              ; X = debut de l'ecran
        ldd     #0              ; D = 0 (deux octets nuls)
cl1     std     ,x++            ; ecrit 2 octets a 0 ; X avance de 2
        cmpx    #8000           ; CMPX compare X a 8000 (fin de l'ecran)
        blo     cl1             ; BLO : plus petit (non signe) -> on continue
        lda     PRA             ; selectionne la memoire "couleur"
        anda    #$FE            ; bit 0 a 0
        sta     PRA
        lda     ,s              ; A = couleur (lue sur la pile sans la depiler)
        tfr     a,b             ; B = meme couleur -> D = 2 fois la couleur
        ldx     #0              ; retour au debut de l'ecran
cl2     std     ,x++            ; remplit la memoire couleur
        cmpx    #8000           ; jusqu'a 8000
        blo     cl2
        puls    a,pc            ; depile A et revient

* L'adresse ecran d'une case (colonne, ligne) = ligne*320 + colonne.
* ligne*320 est lu dans la table rowtab (plus rapide qu'un calcul).
*----------------------------------------------------------------
* dessin d'un motif 8x8 : A=colonne B=ligne U=motif, couleur dans tcol
drawpat pshs    a,b,x,u         ; on sauvegarde les registres utilises
        ldx     #rowtab         ; table des adresses de debut de ligne
        aslb                    ; B = ligne*2 (chaque entree fait 2 octets)
        ldx     b,x             ; X = rowtab[ligne] = ligne*320
        leax    a,x             ; X = X + colonne -> adresse du haut de la case
        lda     PRA             ; memoire "forme"...
        ora     #1
        sta     PRA
        lda     ,u              ; 1re ligne du motif...
        sta     ,x              ; ...en haut de la case
        lda     1,u             ; 2e ligne du motif...
        sta     40,x            ; ...une ligne de pixels plus bas (+40 octets)
        lda     2,u
        sta     80,x
        lda     3,u
        sta     120,x
        lda     4,u
        sta     160,x
        lda     5,u
        sta     200,x
        lda     6,u
        sta     240,x
        lda     7,u
        sta     280,x           ; 8e ligne = 7*40 plus bas
        lda     PRA             ; memoire "couleur"...
        anda    #$FE
        sta     PRA
        lda     tcol            ; la meme couleur...
        sta     ,x              ; ...pour les 8 lignes de pixels
        sta     40,x
        sta     80,x
        sta     120,x
        sta     160,x
        sta     200,x
        sta     240,x
        sta     280,x
        puls    a,b,x,u,pc      ; restaure et revient

* Les tuiles 0 a 9 (vide, pieces, briques, flash) ont une couleur
* differente sur chaque ligne de pixels (table tilecol) : c'est ce
* qui donne le reflet et l'ombre des blocs. Les autres utilisent tcol.
* tuile numero tnum en A=colonne B=ligne
drawtile pshs   a,b,u,y
        ldb     tnum            ; numero de tuile
        lda     #8              ; x 8 octets par tuile
        mul                     ; MUL : D = A x B
        ldu     #tiles          ; U = debut de la table des motifs
        leau    d,u             ; U = motif de la tuile
        ldy     #tilecol        ; table des couleurs par ligne
        leay    d,y             ; Y = couleurs de la tuile
        lda     ,s              ; remet la colonne (sauvee sur la pile)...
        ldb     1,s             ; ...et la ligne
        tst     tnum            ; TST : compare a 0
        beq     dt1             ; tuile 0 -> couleurs par ligne
        pshs    a               ; garde A
        lda     tnum            ; numero de tuile
        cmpa    #10             ; >= 10 ?
        puls    a               ; PULS ne change pas les drapeaux
        bhs     dt2             ; BHS : >= (non signe) -> une seule couleur
dt1     bsr     drawpc2         ; dessin multicolore
        puls    a,b,u,y,pc
dt2     lbsr    drawpat         ; dessin une couleur (LBSR = BSR longue portee)
        puls    a,b,u,y,pc

* meme chose que drawpat mais la couleur change a chaque ligne
* motif U avec 8 couleurs Y (une par ligne)
drawpc2 pshs    a,b,x,u
        ldx     #rowtab
        aslb
        ldx     b,x
        leax    a,x
        lda     PRA
        ora     #1
        sta     PRA
        lda     ,u
        sta     ,x
        lda     1,u
        sta     40,x
        lda     2,u
        sta     80,x
        lda     3,u
        sta     120,x
        lda     4,u
        sta     160,x
        lda     5,u
        sta     200,x
        lda     6,u
        sta     240,x
        lda     7,u
        sta     280,x
        lda     PRA
        anda    #$FE
        sta     PRA
        lda     ,y              ; couleur de la 1re ligne de pixels
        sta     ,x
        lda     1,y             ; couleur de la 2e ligne, etc.
        sta     40,x
        lda     2,y
        sta     80,x
        lda     3,y
        sta     120,x
        lda     4,y
        sta     160,x
        lda     5,y
        sta     200,x
        lda     6,y
        sta     240,x
        lda     7,y
        sta     280,x
        puls    a,b,x,u,pc

* ----- putch : dessine le caractere ASCII "chr"
* caractere chr en A=colonne B=ligne
putch   pshs    a,b,u
        ldb     chr             ; code ASCII du caractere
        subb    #32             ; la police commence au caractere 32 (espace)
        lda     #8              ; 8 octets par caractere
        mul                     ; D = (code-32)*8
        ldu     #font           ; debut de la police
        leau    d,u             ; U = dessin du caractere
        lda     ,s
        ldb     1,s
        lbsr    drawpat         ; dessine avec la couleur tcol
        puls    a,b,u,pc

* ----- text : affiche une chaine terminee par 0
* texte X (termine par 0) en A=colonne B=ligne
text    pshs    x               ; garde le debut de la chaine
        sta     tcx             ; colonne courante
        stb     tcy             ; ligne
tx1     lda     ,x+             ; lit un caractere, X avance
        beq     tx2             ; 0 = fin de chaine
        sta     chr             ; caractere a dessiner
        lda     tcx
        ldb     tcy
        bsr     putch
        inc     tcx             ; colonne suivante
        bra     tx1
tx2     puls    x,pc            ; restaure X et revient

* ----- fillrect : remplit un rectangle avec la tuile tnum
* rectangle de tuiles tnum : A=col B=ligne, rw x rh
fillrect sta    fx0             ; colonne de depart
        stb     fy              ; ligne courante
fr1     lda     fx0             ; pour chaque ligne : on repart de la colonne de depart
        sta     fx
        ldb     rw              ; nombre de cases par ligne
        stb     fcnt            ; compteur
fr2     lda     fx              ; dessine une case
        ldb     fy
        jsr     drawtile
        inc     fx              ; case suivante
        dec     fcnt
        bne     fr2
        inc     fy              ; ligne suivante
        dec     rh              ; une ligne de moins a faire
        bne     fr1
        rts

* ----- row3 : une ligne de cadre = gauche, milieu x (bw-2), droite
* ligne de cadre : A=col B=ligne, largeur bw, tuiles tl tm tr
row3    sta     fx
        stb     fy
        lda     tl              ; tuile de gauche
        sta     tnum
        lda     fx
        jsr     drawtile
        lda     bw              ; largeur totale...
        suba    #2              ; ...moins les 2 coins
        sta     fcnt
r3a     inc     fx
        lda     tm              ; tuile du milieu
        sta     tnum
        lda     fx
        ldb     fy
        jsr     drawtile
        dec     fcnt
        bne     r3a
        inc     fx
        lda     tr              ; tuile de droite
        sta     tnum
        lda     fx
        ldb     fy
        jmp     drawtile        ; JMP : drawtile fera le RTS a notre place

* ----- box : cadre arrondi, interieur rempli de gris
* cadre : A=col B=ligne, taille bw x bh
box     sta     bx              ; position du coin haut gauche
        stb     by
        lda     #T_TL           ; ligne du haut : coin, bord, coin
        sta     tl
        lda     #T_T
        sta     tm
        lda     #T_TR
        sta     tr
        lda     bx
        ldb     by
        bsr     row3            ; dessine la ligne du haut
        lda     bh              ; nombre de lignes du milieu = hauteur - 2
        suba    #2
        sta     bcnt
        lda     #T_L            ; lignes du milieu : bord, vide, bord
        sta     tl
        lda     #T_PAN
        sta     tm
        lda     #T_R
        sta     tr
bx1     inc     by              ; ligne suivante
        lda     bx
        ldb     by
        lbsr    row3
        dec     bcnt
        bne     bx1
        inc     by              ; ligne du bas
        lda     #T_BL
        sta     tl
        lda     #T_B
        sta     tm
        lda     #T_BR
        sta     tr
        lda     bx
        ldb     by
        lbra    row3

*----------------------------------------------------------------
* Les nombres sont stockes en BCD : chaque octet contient 2 chiffres
* decimaux (4 bits chacun). $12 $34 $56 = 123456. C'est pratique
* pour l'affichage et l'instruction DAA corrige les additions.
* nombres
* putbcd : X=nombre BCD, B=nb octets, A=colonne, ny=ligne
putbcd  sta     nx              ; colonne du 1er chiffre
        stb     ncnt            ; nombre d'octets restants
        clr     nz              ; nz = 0 : pas encore vu de chiffre non nul
        clr     nlast           ; nlast = 1 quand on arrive au tout dernier chiffre
pb1     lda     ,x+             ; octet suivant (2 chiffres)
        sta     nbyte
        lsra                    ; decalage de 4 bits vers la droite...
        lsra
        lsra
        lsra                    ; ...A = chiffre de gauche
        bsr     pdig            ; affiche ce chiffre
        lda     ncnt            ; dernier octet ?
        cmpa    #1
        bne     pb2
        inc     nlast           ; oui : son 2e chiffre est le dernier
pb2     lda     nbyte
        anda    #15             ; garde les 4 bits de droite = 2e chiffre
        bsr     pdig
        dec     ncnt
        bne     pb1
        rts
pdig    tsta                    ; chiffre nul ?
        bne     pd1             ; non -> on l'affiche
        tst     nz              ; deja affiche un chiffre non nul ?
        bne     pd1             ; oui -> on affiche le 0
        tst     nlast           ; dernier chiffre ?
        bne     pd1             ; oui -> on affiche 0 (le nombre vaut 0)
        lda     #32             ; sinon espace (pas de zeros a gauche)
        bra     pd2
pd1     ldb     #1              ; a partir de maintenant on affiche tous les chiffres
        stb     nz
        adda    #48             ; chiffre -> code ASCII ('0' = 48)
pd2     sta     chr
        lda     nx
        ldb     ny
        jsr     putch           ; affiche
        inc     nx              ; colonne suivante
        rts

* ----- bin2bcd : convertit 0..99 en BCD (ex : 42 -> $42)
* A (0..99) -> A en BCD
bin2bcd clrb                    ; B comptera les dizaines (en BCD)
bb1     cmpa    #10             ; reste >= 10 ?
        blo     bb2             ; non : fini
        suba    #10             ; enleve 10...
        addb    #$10            ; ...et ajoute 1 dizaine (+$10)
        bra     bb1
bb2     pshs    b
        adda    ,s+             ; A = unites + dizaines (ADDA ,S+ depile B au passage)
        rts

* ----- bcd2bin : l'inverse ($42 -> 42)
* A (BCD) -> A binaire
bcd2bin pshs    a
        lsra                    ; chiffre des dizaines
        lsra
        lsra
        lsra
        ldb     #10
        mul                     ; B = dizaines x 10
        lda     ,s+             ; reprend l'octet d'origine
        anda    #15             ; unites
        pshs    b
        adda    ,s+             ; A = dizaines*10 + unites
        rts

* ----- addbcd3 : score = score + nombre BCD de 3 octets (en X)
* ajoute le nombre BCD de 3 octets pointe par X au score
addbcd3 lda     score+2         ; on additionne en commencant par la droite
        adda    2,x
        daa                     ; DAA corrige le resultat pour qu'il reste en BCD
        sta     score+2
        lda     score+1
        adca    1,x             ; ADCA : ajoute aussi la retenue de l'octet precedent
        daa
        sta     score+1
        lda     score
        adca    ,x
        daa
        sta     score
        bcc     ab9             ; pas de retenue finale -> fini
maxsc   lda     #$99            ; sinon le score plafonne a 999999
        sta     score
        sta     score+1
        sta     score+2
ab9     rts

* Le buzzer est un haut-parleur tout simple (bit 0 de PRB) : pour
* faire une note on le met a 1, on attend, on le met a 0, on attend,
* et on recommence. Plus l'attente est courte, plus le son est aigu.
*----------------------------------------------------------------
* sons : X = sequence (amp, demi-periode, nb periodes), fin = $FF
playseq lda     ,x              ; 1er octet de la note : amplitude (ou $FF = fin)
        cmpa    #$FF
        beq     ps9             ; fin du morceau
        ldy     3,x             ; Y = nombre de periodes (duree)
        pshs    x               ; garde la position dans le morceau
        ldx     1,x             ; X = demi-periode (hauteur de la note)
        bsr     tone            ; joue la note
        puls    x
        leax    5,x             ; note suivante (5 octets par note)
        bra     playseq
ps9     clr     PRB             ; silence
        rts

* A = amplitude (1 ou 0), X = demi-periode, Y = nb de periodes
tone    sta     tamp            ; 1 = son, 0 = silence
        stx     thalf           ; duree d'une demi-periode
to1     lda     tamp
        sta     PRB             ; haut-parleur en position "1"
        ldx     thalf
to2     leax    -1,x            ; boucle d'attente : 8 cycles par tour
        bne     to2
        clr     PRB             ; haut-parleur en position "0"
        ldx     thalf
to3     leax    -1,x
        bne     to3
        leay    -1,y            ; une periode de faite
        bne     to1             ; encore des periodes ?
        rts

*----------------------------------------------------------------
* Generateur pseudo-aleatoire : registre a decalage 16 bits (LFSR).
* On decale 8 fois, le bit qui sort decide si on melange avec $B4.
* nombre aleatoire (LFSR 16 bits) -> A
rnd     pshs    b
        ldb     #8              ; 8 decalages = 8 nouveaux bits
rn1     lsr     seed            ; LSR : decale l'octet haut a droite, bit 0 -> C
        ror     seed+1          ; ROR : C entre a gauche de l'octet bas
        bcc     rn2             ; bit sorti = 0 : rien a faire
        lda     seed            ; bit sorti = 1 : on inverse certains bits
        eora    #$B4            ; EORA = OU exclusif
        sta     seed
rn2     decb
        bne     rn1
        lda     seed+1          ; A = nombre aleatoire 0..255
        puls    b,pc

* Astuce : A (0..255) x 7 donne D ; l'octet haut A vaut alors 0..6.
* piece aleatoire 0..6 (nouveau tirage si identique, comme sur GB)
pickrnd bsr     rnd             ; nombre aleatoire
        ldb     #7
        mul                     ; A = hasard x 7 / 256 = 0..6
        cmpa    piece           ; meme piece que la precedente ?
        bne     pr9             ; non : on la garde
        bsr     rnd             ; oui : on retire une fois (comme la Game Boy)
        ldb     #7
        mul
pr9     rts

* L'ecran titre joue la musique et gere le menu entre chaque bout de
* note (40 ms) : c'est pour ca que les touches restent reactives.
*================================================================
*  ECRAN TITRE
*================================================================
title   lds     savesp          ; repart d'une pile propre
        lda     #CTITLE         ; fond bleu nuit, texte blanc
        jsr     cls
        lda     #8              ; tuile 8 = brique
        sta     tnum
        lda     #CBRICK
        sta     tcol
        lda     #40             ; 40 cases de large
        sta     rw              ; 2 lignes de haut
        lda     #2
        sta     rh
        clra                    ; colonne 0
        clrb                    ; ligne 0
        jsr     fillrect        ; briques en haut
        lda     #40
        sta     rw
        lda     #2
        sta     rh
        clra
        ldb     #23             ; ligne 23
        jsr     fillrect        ; briques en bas
* gros TETRIS en couleurs
        ldu     #bigfont        ; dessins des 6 grosses lettres (4 tuiles chacune)
        ldy     #bigcol         ; couleur de chaque lettre
        lda     #14             ; colonne de depart
        sta     fx
bt1     ldb     ,y+             ; couleur de cette lettre
        stb     tcol
        lda     fx
        ldb     #4              ; ligne 4
        jsr     drawpat         ; quart haut gauche
        leau    8,u             ; morceau suivant
        inca                    ; colonne + 1
        jsr     drawpat         ; quart haut droit
        leau    8,u
        deca                    ; colonne - 1
        incb                    ; ligne + 1
        jsr     drawpat         ; quart bas gauche
        leau    8,u
        inca
        jsr     drawpat
        leau    8,u             ; quart bas droit
        inca
        sta     fx              ; lettre suivante : 2 colonnes plus loin
        cmpa    #26             ; 6 lettres dessinees ?
        bne     bt1
        lda     #CTITLE
        sta     tcol
        ldx     #s_sub          ; sous-titre
        lda     #6
        ldb     #7
        jsr     text
        ldx     #s_top          ; "TOP"
        lda     #14
        ldb     #9
        jsr     text
        jsr     showtop         ; affiche le record
        lda     #CHELP
        sta     tcol
        ldx     #help           ; 6 lignes d'aide
        ldb     #15             ; a partir de la ligne 15
ti1     lda     #4              ; colonne 4
        jsr     text
        ldb     tcy             ; ligne courante
ti2     lda     ,x+             ; avance X jusqu'apres le 0 de la chaine
        bne     ti2
        incb                    ; ligne suivante
        lda     ,x              ; 0 juste derriere = fin de la liste
        bne     ti1
        lda     #CYEL
        sta     tcol
        ldx     #s_start
        lda     #4
        ldb     #22
        jsr     text
        ldx     #menutab        ; au titre, les touches ont un autre role
        stx     ktab
        jsr     showmenu        ; affiche TYPE / NIVEAU / HAUTEUR
        jsr     scan            ; initialise "prevk"
* musique + attente
tm0     ldx     #music          ; X = debut de la musique
tm1     lda     ,x
        cmpa    #$FF            ; fin de la musique ?
        beq     tm0             ; oui : on la reprend au debut
        ldy     3,x             ; duree du morceau de note
        pshs    x
        ldx     1,x             ; hauteur
        jsr     tone            ; joue ~40 ms
        jsr     rnd             ; fait tourner le hasard (il depend du temps d'attente)
        jsr     scan            ; lit le clavier
        puls    x
        leax    5,x             ; morceau suivant
        lda     edge            ; touches nouvellement enfoncees
        bita    #K_STOP         ; STOP ?
        lbne    quit            ; -> retour au BASIC
        bita    #K_DROP         ; ENTREE ou ESPACE ?
        lbne    newgame         ; -> on joue
        jsr     menukey         ; fleches : menu
        bra     tm1

* Haut/bas : change la ligne choisie. Gauche/droite : change la valeur.
* touches du menu (preserve X)
menukey pshs    x
        lda     edge
        bita    #K_ROTA         ; fleche haut ?
        beq     mk1
        tst     msel            ; deja en haut ?
        lbeq    mk9x
        dec     msel            ; ligne precedente
        lbra    mk9
mk1     bita    #K_DOWN         ; fleche bas ?
        beq     mk2
        lda     msel
        cmpa    gtype           ; ligne max = 1 en type A, 2 en type B
        lbhi    mk9x            ; LBHI : plus grand (non signe) -> on ne bouge pas
        inc     msel            ; ligne suivante
        lbra    mk9
mk2     bita    #K_LEFT+K_RIGHT  ; gauche ou droite ?
        lbeq    mk9x
        ldb     msel            ; quelle ligne ?
        beq     mkt             ; 0 = TYPE
        cmpb    #1
        beq     mkl             ; 1 = NIVEAU
        bita    #K_LEFT         ; sinon 2 = HAUTEUR : gauche ?
        beq     mkh1
        tst     bheight         ; deja 0 ?
        lbeq    mk9x
        dec     bheight
        lbra    mk9
mkh1    lda     bheight         ; droite : maxi 5
        cmpa    #5
        lbhs    mk9x
        inc     bheight
        lbra    mk9
mkl     bita    #K_LEFT         ; NIVEAU : gauche ?
        beq     mkl1
        tst     startlv
        lbeq    mk9x
        dec     startlv
        lbra    mk9
mkl1    lda     startlv         ; droite : maxi 9
        cmpa    #9
        lbhs    mk9x
        inc     startlv
        lbra    mk9
mkt     lda     gtype           ; TYPE : on bascule A <-> B
        eora    #1              ; EOR #1 inverse le bit 0
        sta     gtype
        ldx     #hisA
        tsta                    ; type A ?
        beq     mkt1
        ldx     #hisB           ; type B : autre record
mkt1    stx     hisptr
        jsr     showtop         ; affiche le bon record
        tst     gtype           ; en type A, la ligne HAUTEUR n'existe pas
        bne     mk9
        lda     msel
        cmpa    #1
        bls     mk9
        lda     #1
        sta     msel
mk9     bsr     showmenu        ; redessine le menu
mk9x    puls    x,pc

* ----- showtop : record du type en cours, ligne 9
showtop lda     #CYEL
        sta     tcol
        lda     #9
        sta     ny
        ldx     hisptr          ; X = adresse du record (hisA ou hisB)
        ldb     #3              ; 3 octets BCD = 6 chiffres
        lda     #19             ; colonne 19
        jmp     putbcd          ; putbcd fera le RTS

* ----- showmenu : les 3 lignes du menu et le curseur ">"
showmenu lda    #CTITLE
        sta     tcol
        ldx     #s_mtype
        lda     #12
        ldb     #11
        jsr     text
        ldx     #s_mlev
        lda     #12
        ldb     #12
        jsr     text
        ldx     #s_mhaut
        lda     #12
        ldb     #13
        jsr     text
        lda     #CYEL
        sta     tcol
        lda     gtype           ; 0 ou 1...
        adda    #65             ; ...+ 'A' (65) = 'A' ou 'B'
        sta     chr
        lda     #24
        ldb     #11
        jsr     putch
        lda     startlv
        adda    #48             ; + '0'
        sta     chr
        lda     #24
        ldb     #12
        jsr     putch
        lda     bheight
        adda    #48
        tst     gtype           ; en type A...
        bne     sm1
        lda     #45             ; ...on affiche '-' (45)
sm1     sta     chr
        lda     #24
        ldb     #13
        jsr     putch
        clr     fi              ; fi = numero de ligne 0..2
sm2     lda     #32             ; espace par defaut
        ldb     fi
        cmpb    msel            ; ligne selectionnee ?
        bne     sm3
        lda     #62             ; oui : '>' (62)
sm3     sta     chr
        addb    #11             ; ligne ecran = 11 + fi
        lda     #10             ; colonne 10
        jsr     putch
        inc     fi
        lda     fi
        cmpa    #3
        bne     sm2
        rts

* Le plateau "board" : 24 lignes de 16 octets. Colonnes 3..12 = puits
* (10 cases). Colonnes 0-2 et 13-15 = murs ($FF), lignes 21-23 = sol.
* Lignes 0-2 = invisibles au-dessus du puits. Une case vaut 0 si vide,
* sinon le numero de tuile de la piece posee (1..7). Grace aux murs,
* le test de collision n'a jamais besoin de verifier les bords.
*================================================================
*  NOUVELLE PARTIE
*================================================================
newgame clr     PRB             ; coupe le son
        lds     savesp          ; pile propre
* plateau : 24 lignes x 16 colonnes, murs = $FF
        ldx     #board
        clrb                    ; B = numero de ligne
ng1     lda     #$FF            ; mur
        sta     ,x              ; colonnes 0, 1, 2...
        sta     1,x
        sta     2,x
        sta     13,x            ; ...et 13, 14, 15
        sta     14,x
        sta     15,x
        clra                    ; A = 0 (case vide)...
        cmpb    #21             ; ...sauf pour les lignes 21 a 23 :
        blo     ng2
        lda     #$FF            ; sol
ng2     sta     3,x             ; colonnes 3 a 12
        sta     4,x
        sta     5,x
        sta     6,x
        sta     7,x
        sta     8,x
        sta     9,x
        sta     10,x
        sta     11,x
        sta     12,x
        leax    16,x            ; ligne suivante (+16 octets)
        incb
        cmpb    #24             ; 24 lignes ?
        bne     ng1
        ldx     #rowcnt         ; nombre de cases occupees par ligne
        ldb     #24
ng3     clr     ,x+             ; tout a zero
        decb
        bne     ng3
        clr     score           ; score a 0
        clr     score+1
        clr     score+2
        clr     lines           ; lignes a 0
        clr     lines+1
        clr     topout          ; pas encore perdu
        clr     dropcnt         ; points de descente rapide
        clr     bdone           ; type B pas encore gagne
        lda     startlv
        sta     level           ; niveau de depart
        jsr     setspd          ; vitesse de chute du niveau
        ldx     #keytab         ; touches du jeu
        stx     ktab
        tst     gtype           ; type B ?
        beq     ngd             ; non : on saute
        lda     #25             ; 25 lignes a faire
        sta     blines
        lda     #$25            ; meme valeur en BCD pour l'affichage
        sta     lines+1
        jsr     garbage         ; lignes de dechets
* decor
ngd     lda     #CTEXT          ; fond gris
        jsr     cls
        lda     #8              ; tout l'ecran en briques
        sta     tnum
        lda     #40
        sta     rw
        lda     #25
        sta     rh
        clra
        clrb
        jsr     fillrect
        lda     #CTEXT
        sta     tcol
        ldx     #boxtab         ; liste des cadres a dessiner
nb1     lda     ,x+             ; colonne
        cmpa    #$FF            ; $FF = fin de liste
        beq     nb2
        ldb     ,x+             ; ligne
        pshs    a,b             ; garde colonne et ligne
        lda     ,x+             ; largeur
        sta     bw
        lda     ,x+             ; hauteur
        sta     bh
        puls    a,b
        pshs    x               ; garde la position dans la liste
        jsr     box             ; dessine le cadre
        puls    x
        bra     nb1
nb2     ldx     #labtab         ; liste des libelles (NEXT, SCORE...)
nb3     lda     ,x+             ; colonne
        cmpa    #$FF
        beq     nb4
        ldb     ,x+             ; ligne
        ldu     ,x++            ; U = adresse du texte (2 octets)
        pshs    x
        tfr     u,x             ; TFR : copie U dans X
        jsr     text
        puls    x
        bra     nb3
nb4
        jsr     drawfield       ; dessine le puits (vide ou avec les dechets)
        jsr     drawstats       ; scores
        lda     #$FF            ; pas encore de piece
        sta     piece
        jsr     pickrnd         ; tire la 1re piece "suivante"
        sta     nextp
        jsr     spawn           ; et fait apparaitre la 1re piece

* Chaque tour de boucle = une image (1/50 s) : on lit le clavier,
* on gere les deplacements puis la chute.
*================================================================
*  BOUCLE DE JEU (une iteration par image)
*================================================================
gloop   jsr     vsync           ; attend l'image suivante
        jsr     scan            ; lit le clavier
        lda     edge            ; touches nouvellement enfoncees
        bita    #K_STOP         ; STOP ?
        lbne    title           ; retour au titre
        bita    #K_PAUSE        ; P ?
        beq     g1
        jsr     pause           ; pause
g1      lda     edge
        bita    #K_ROTA         ; rotation A ?
        beq     g2
        lda     #1              ; +1 quart de tour
        jsr     rotate
g2      lda     edge
        bita    #K_ROTB         ; rotation B ?
        beq     g3
        lda     #3              ; +3 quarts de tour = -1
        jsr     rotate
* DAS (comme sur Game Boy) : 1er appui = 1 case, puis si on garde la
* touche, attente de DASD images, puis 1 case toutes les DASR images.
* gauche / droite avec repetition (DAS)
g3      lda     keys            ; touches tenues
        anda    #K_LEFT+K_RIGHT  ; garde seulement gauche et droite
        cmpa    #K_LEFT         ; gauche seule ?
        beq     gl
        cmpa    #K_RIGHT        ; droite seule ?
        bne     g4              ; aucune (ou les deux) : rien
        ldd     #1              ; deplacement +1
        bra     gh
gl      ldd     #-1             ; deplacement -1
gh      std     dxv             ; dxv = deplacement voulu
        lda     edge            ; la touche vient-elle d'etre enfoncee ?
        anda    #K_LEFT+K_RIGHT
        beq     gh2             ; non : touche tenue -> on gere la repetition
        lda     #DASD           ; oui : on bouge tout de suite et on arme le delai
        sta     dascnt
        bra     gh3
gh2     dec     dascnt          ; touche tenue : on decompte
        bne     g4              ; pas encore le moment
        lda     #DASR           ; puis on repete a cette cadence
        sta     dascnt
gh3     ldd     pos             ; position actuelle...
        addd    dxv             ; ...+ deplacement
        ldu     shptr           ; meme forme
        jsr     trymove         ; essaie de bouger (si la place est libre)
* chute directe
g4      lda     edge            ; ENTREE vient d'etre enfoncee ?
        bita    #K_DROP
        beq     g5
        jsr     hdrop           ; chute directe + pose de la piece
        bra     gend
* descente rapide
g5      lda     keys            ; touche bas tenue ?
        bita    #K_DOWN
        bne     g6
        lda     #1              ; relachee : on autorise la descente rapide
        sta     downok          ; (pour la piece suivante, il faut relacher puis rappuyer)
        bra     g7
g6      tst     downok          ; autorisee ?
        beq     g7
        lda     edge
        bita    #K_DOWN         ; juste enfoncee ?
        beq     g6b
        lda     #1              ; oui : descente immediate
        sta     sdcnt
g6b     dec     sdcnt           ; decompte
        bne     g7
        lda     #SDR            ; puis une ligne toutes les SDR images
        sta     sdcnt
        jsr     stepdn          ; descend d'une ligne
        bne     glock           ; impossible : la piece se pose
        inc     dropcnt         ; +1 point par ligne descendue
        lda     speed           ; la gravite repart de zero
        sta     gcnt
        lbra    gloop
* La gravite : toutes les "speed" images la piece descend d'une ligne.
* gravite
g7      dec     gcnt            ; compteur de gravite
        lbne    gloop           ; pas encore : image suivante
        lda     speed
        sta     gcnt            ; recharge le compteur
        jsr     stepdn          ; descend d'une ligne
        lbeq    gloop           ; reussi : on continue
glock   jsr     lockpc          ; bloquee : on pose la piece
gend    tst     bdone           ; type B termine ?
        lbne    bwin
        tst     topout          ; perdu ?
        lbeq    gloop           ; non : on continue
        jmp     gover           ; oui : fin de partie

* Les formes sont dans la table "shapes" : 7 pieces x 4 rotations x
* 4 cases. Chaque case = decalage dans le plateau (ligne*16+colonne).
*----------------------------------------------------------------
* rotation : A = +1 (A) ou +3 (B)
rotate  adda    rot             ; nouvelle rotation = rotation + 1 ou + 3...
        anda    #3              ; ...modulo 4 (AND #3 garde les 2 bits de droite)
        sta     nrot
        lda     piece           ; piece x 16...
        lsla                    ; (LSLA = decalage a gauche = x 2)
        lsla
        lsla
        lsla
        ldb     nrot            ; + rotation x 4
        lslb
        lslb
        pshs    b
        adda    ,s+             ; A = piece*16 + rotation*4
        tfr     a,b
        ldu     #shapes
        leau    b,u             ; U = les 4 cases de la forme tournee
        ldd     pos             ; meme position
        jsr     trymove         ; essaie
        bne     ro9             ; pas la place : on ne tourne pas
        lda     nrot
        sta     rot             ; rotation acceptee
        ldx     #sfxrot         ; petit bip
        jsr     playseq
ro9     rts

* ----- setsh : calcule shptr = forme de la piece courante
* shptr <- shapes + piece*16 + rot*4
setsh   lda     piece
        lsla
        lsla
        lsla
        lsla
        ldb     rot
        lslb
        lslb
        pshs    b
        adda    ,s+
        tfr     a,b
        ldx     #shapes
        abx                     ; ABX : X = X + B (B non signe)
        stx     shptr
        rts

* ----- fits : la piece tient-elle a la position D ?
* On regarde les 4 cases : il suffit qu'une ne soit pas 0 (piece,
* mur ou sol) pour que ce soit non. Resultat : Z = 1 si ca tient.
* D = position, U = forme -> Z=1 si la piece tient
fits    ldx     #board
        leax    d,x             ; X = adresse de la position dans le plateau
        ldb     ,u              ; decalage de la 1re case
        lda     b,x             ; lit la case du plateau
        bne     ft9             ; occupee -> ne tient pas
        ldb     1,u             ; 2e case
        lda     b,x
        bne     ft9
        ldb     2,u             ; 3e case
        lda     b,x
        bne     ft9
        ldb     3,u             ; 4e case
        lda     b,x
ft9     rts                     ; Z reste celui du dernier test

* ----- trymove : si la piece tient en D (forme U), on l'efface a
* l'ancienne place et on la redessine a la nouvelle.
* deplacement vers D/U si possible (Z=1 si fait)
trymove std     npos            ; position candidate
        stu     nsh             ; forme candidate
        bsr     fits
        bne     tm9             ; ne tient pas : on sort avec Z = 0
        clr     tnum            ; tuile 0 = vide
        bsr     drawpc          ; efface la piece
        ldd     npos            ; nouvelle position...
        std     pos
        ldu     nsh             ; ...et nouvelle forme
        stu     shptr
        lda     piece           ; tuile = numero de piece + 1
        inca
        sta     tnum
        bsr     drawpc          ; dessine la piece
        clra                    ; CLRA met Z = 1 : "c'est fait"
tm9     rts

stepdn  ldd     pos             ; position + 16 = une ligne plus bas
        addd    #16
        ldu     shptr
        bra     trymove         ; essaie (trymove fera le RTS)

* dessin de la piece courante avec la tuile tnum
drawpc  lda     #CFIELD
        sta     tcol
        ldu     shptr
        lda     #4              ; 4 cases a dessiner
        sta     pcnt
dp1     ldb     ,u+             ; decalage de la case
        clra                    ; D = decalage (A = 0)
        addd    pos             ; + position = index dans le plateau
        bsr     idx2cr          ; -> colonne et ligne ecran
        cmpb    #3              ; ligne cachee (0 a 2) ?
        blo     dp2             ; oui : on ne dessine pas
        jsr     drawtile
dp2     dec     pcnt            ; case suivante
        bne     dp1
        rts

* index = ligne*16 + colonne : on divise par 16 pour avoir la ligne
* D = index plateau -> A = colonne ecran, B = ligne
idx2cr  pshs    b               ; garde l'octet bas (il contient la colonne)
        lsra                    ; decale D de 4 bits vers la droite
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        lda     ,s+             ; reprend l'octet bas
        anda    #15             ; colonne = index modulo 16
        adda    #FX             ; + decalage de l'ecran
        rts

* chute directe
hdrop   clr     tnum            ; efface la piece
        bsr     drawpc
hd1     ldd     pos             ; essaie une ligne plus bas
        addd    #16
        ldu     shptr
        lbsr    fits
        bne     hd2             ; bloque : on s'arrete
        ldd     pos             ; descend
        addd    #16
        std     pos
        inc     dropcnt         ; +1 point par ligne
        bra     hd1
hd2     lda     piece           ; redessine la piece a sa place finale
        inca
        sta     tnum
        bsr     drawpc          ; (on continue directement dans lockpc)

* ----- lockpc : la piece est posee, on l'inscrit dans le plateau
* pose de la piece
lockpc  ldu     shptr
        lda     #4              ; 4 cases
        sta     pcnt
        lda     piece
        inca
        sta     ltile           ; valeur a ecrire = numero de tuile
lk1     ldb     ,u+             ; decalage de la case
        clra
        addd    pos             ; index dans le plateau
        std     tmpw            ; garde l'index
        ldx     #board
        leax    d,x             ; adresse de la case
        lda     ltile
        sta     ,x              ; la case devient occupee
        ldd     tmpw            ; reprend l'index
        lsra                    ; divise par 16 -> ligne
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        cmpb    #3              ; posee dans les lignes cachees ?
        bhs     lk2             ; non : c'est bon
        lda     #1              ; oui : la pile deborde -> perdu
        sta     topout
lk2     ldx     #rowcnt         ; compteur de cases de cette ligne
        abx
        inc     ,x              ; +1
        dec     pcnt            ; case suivante
        bne     lk1
        jsr     addsoft         ; ajoute les points de descente
        tst     topout
        bne     lk9             ; perdu : on s'arrete la
        ldx     #sfxlock        ; bruit de pose
        jsr     playseq
        jsr     chklines        ; lignes completes ?
        jsr     drawstats       ; affiche score, lignes, niveau
        jsr     spawn           ; piece suivante
lk9     rts

* ----- spawn : la piece "suivante" entre en jeu
* nouvelle piece
spawn   lda     nextp
        sta     piece           ; devient la piece courante
        jsr     pickrnd         ; et on en tire une nouvelle
        sta     nextp
        clr     rot             ; rotation de depart
        ldd     #SPAWN          ; en haut au milieu
        std     pos
        jsr     setsh           ; calcule la forme
        clr     dropcnt
        clr     downok          ; il faut relacher "bas" avant de descendre vite
        lda     speed
        sta     gcnt            ; gravite remise a zero
        jsr     drawnext        ; affiche la piece suivante
        ldd     pos             ; la nouvelle piece a-t-elle la place ?
        ldu     shptr
        jsr     fits
        beq     sp2             ; oui
        lda     #1              ; non : perdu
        sta     topout
sp2     lda     piece
        inca
        sta     tnum
        jmp     drawpc          ; dessine la piece

* ----- drawnext : dessine la piece suivante dans le cadre NEXT
* affichage de la piece suivante
drawnext lda    #CTEXT
        sta     tcol
        lda     #T_PAN          ; efface la zone 4x4
        sta     tnum
        lda     #4
        sta     rw
        lda     #4
        sta     rh
        lda     #NXC
        ldb     #NXR
        jsr     fillrect
        lda     nextp
        inca                    ; tuile de cette piece
        sta     tnum
        lda     nextp           ; forme de base (rotation 0)...
        lsla                    ; ...= shapes + piece*16
        lsla
        lsla
        lsla
        ldx     #shapes
        leax    a,x
        lda     #4
        sta     pcnt
dn1     ldb     ,x              ; decalage de la case
        andb    #15             ; colonne dans la forme (0..3)
        addb    #NXC            ; + colonne du cadre
        lda     ,x+             ; meme decalage...
        lsra                    ; /16 = ligne dans la forme
        lsra
        lsra
        lsra
        adda    #NXR            ; + ligne du cadre
        exg     a,b             ; EXG : echange A et B (A = colonne, B = ligne)
        jsr     drawtile
        dec     pcnt
        bne     dn1
        rts

* ----- addsoft : ajoute dropcnt points (1 par ligne descendue vite)
* points de descente rapide / chute directe
addsoft ldb     dropcnt
        beq     as9             ; rien a ajouter
as1     lda     score+2         ; score + 1 en BCD
        adda    #1
        daa
        sta     score+2
        lda     score+1
        adca    #0
        daa
        sta     score+1
        lda     score
        adca    #0
        daa
        sta     score
        bcc     as2
        jsr     maxsc           ; plafond 999999
as2     decb                    ; encore ?
        bne     as1
as9     clr     dropcnt
        rts

*----------------------------------------------------------------
* On ne regarde que les 4 lignes touchees par la piece posee.
* rowcnt[ligne] = 10 veut dire ligne pleine.
* lignes completes
chklines clr    nfull           ; nombre de lignes pleines
        ldd     pos             ; position de la piece
        lsra                    ; /16 = ligne du haut de la piece
        rorb
        lsra
        rorb
        lsra
        rorb
        lsra
        rorb
        stb     r0
        lda     #4              ; 4 lignes a verifier
        sta     pcnt
ck1     ldb     r0              ; ligne courante
        cmpb    #20             ; sous le puits ?
        bhi     ck3             ; oui : on arrete
        cmpb    #3              ; dans les lignes cachees ?
        blo     ck2             ; oui : on passe
        ldx     #rowcnt
        lda     b,x             ; nombre de cases de cette ligne
        cmpa    #10             ; 10 = pleine ?
        bne     ck2
        ldx     #fullrows       ; on la note dans la liste fullrows
        lda     nfull
        stb     a,x
        inc     nfull
ck2     inc     r0              ; ligne suivante
        dec     pcnt
        bne     ck1
ck3     lda     nfull           ; au moins une ligne ?
        bne     ck4
        rts                     ; non : rien a faire
ck4     ldx     #sfxline        ; son normal...
        cmpa    #4              ; 4 lignes = TETRIS ?
        bne     ck5
        ldx     #sfxtetr        ; ...ou son special
ck5     jsr     playseq
        lda     #3              ; clignotement : 3 fois
        sta     fcount
ck6     lda     #9              ; tuile 9 = blanc
        bsr     fillfull        ; lignes pleines en blanc
        ldb     #4              ; 4 images
        jsr     waitf
        clra                    ; tuile 0 = vide
        bsr     fillfull        ; lignes pleines effacees
        ldb     #4
        jsr     waitf
        dec     fcount
        bne     ck6
        jsr     remrows         ; retire les lignes du plateau
        jsr     drawfield       ; redessine le puits
* points = table[nb lignes] x (niveau + 1)
* score
        lda     nfull           ; nb de lignes
        ldb     #3              ; 3 octets par entree
        mul
        ldx     #ptstab         ; table 0 / 40 / 100 / 300 / 1200
        abx                     ; X = points de base
        lda     level
        inca                    ; niveau + 1
        sta     cnt             ; = nombre d'additions
ck7     jsr     addbcd3         ; score + points de base
        dec     cnt
        bne     ck7             ; (niveau+1) fois
        lda     lines+1         ; compteur de lignes (BCD) + nb lignes
        adda    nfull
        daa
        sta     lines+1
        lda     lines
        adca    #0
        daa
        sta     lines
        bcc     ck8
        lda     #$99            ; plafond 9999
        sta     lines
        sta     lines+1
ck8     tst     gtype           ; type A ?
        lbeq    calclv          ; oui : calcul du niveau
        lda     blines          ; type B : lignes restantes...
        suba    nfull           ; ...moins les lignes faites
        bhi     ck9             ; encore des lignes a faire ?
        clra                    ; non : 0...
        inc     bdone           ; ...et c'est gagne
ck9     sta     blines
        jsr     bin2bcd         ; en BCD pour l'affichage
        sta     lines+1
        clr     lines
        rts

* ----- fillfull : dessine la tuile A sur toutes les lignes pleines
* A = tuile pour toutes les lignes pleines
fillfull sta    tnum            ; tuile a utiliser
        lda     #CFIELD
        sta     tcol
        clr     fi              ; fi = numero dans la liste
ff1     ldx     #fullrows
        lda     fi
        ldb     a,x             ; B = ligne ecran de cette ligne pleine
        stb     fy
        lda     #FLD            ; 1re colonne du puits
        sta     fx
        lda     #10             ; 10 cases
        sta     fcnt
ff2     lda     fx
        ldb     fy
        jsr     drawtile
        inc     fx
        dec     fcnt
        bne     ff2
        inc     fi              ; ligne pleine suivante
        lda     fi
        cmpa    nfull           ; toutes faites ?
        bne     ff1
        rts

* Pour chaque ligne pleine, on recopie chaque ligne du dessus une ligne
* plus bas (de bas en haut), puis on vide la ligne 0.
* suppression des lignes pleines (dans l'ordre croissant)
remrows clr     fi
rr1     ldx     #fullrows
        lda     fi
        ldb     a,x
        stb     rrow            ; rrow = ligne a remplir
rr2     ldb     rrow
        beq     rr4             ; ligne 0 : plus rien au-dessus
        clra                    ; D = ligne x 16 (4 decalages de D vers la gauche)
        lslb                    ; (ROLA recupere le bit sorti de B)
        rola
        lslb
        rola
        lslb
        rola
        lslb
        rola
        ldx     #board
        leax    d,x             ; X = debut de cette ligne dans le plateau
        ldb     #16             ; 16 octets par ligne
rr3     lda     -16,x           ; octet de la ligne du dessus (16 octets avant)...
        sta     ,x+             ; ...copie ici
        decb
        bne     rr3
        ldx     #rowcnt         ; meme chose pour le compteur de cases :
        ldb     rrow
        abx
        lda     -1,x            ; compteur de la ligne du dessus...
        sta     ,x              ; ...recopie
        dec     rrow            ; on remonte d'une ligne
        bra     rr2
rr4     ldx     #board+3        ; ligne 0 : on vide les colonnes 3 a 12
        ldb     #10
rr5     clr     ,x+
        decb
        bne     rr5
        clr     rowcnt          ; et son compteur
        inc     fi              ; ligne pleine suivante
        lda     fi
        cmpa    nfull
        bne     rr1
        rts

* ----- drawfield : redessine les 18 lignes visibles du puits
* redessine tout le puits
drawfield lda   #CFIELD
        sta     tcol
        lda     #3              ; ligne ecran 3 (= ligne 3 du plateau)
        sta     fy
        ldx     #board+3*16+3   ; 1re case visible du plateau
df1     lda     #FLD
        sta     fx
        lda     #10             ; 10 cases par ligne
        sta     fcnt
df2     lda     ,x+             ; contenu de la case = numero de tuile
        sta     tnum
        lda     fx
        ldb     fy
        jsr     drawtile
        inc     fx
        dec     fcnt
        bne     df2
        leax    6,x             ; saute les 6 octets de mur (fin + debut de ligne)
        inc     fy
        lda     fy
        cmpa    #21             ; jusqu'a la ligne 20
        bne     df1
        rts

* niveau = niveau de depart + lignes/10 (plafonne a 99)
* niveau = max(niveau, lignes/10)
calclv  lda     lines           ; lignes (BCD) : octet des milliers/centaines
        jsr     bcd2bin         ; en binaire
        cmpa    #25             ; au-dela de 2500 lignes on plafonne
        bhs     cv1
        ldb     #10
        mul                     ; B = centaines x 10 (en dizaines)
        lda     lines+1         ; octet dizaines/unites
        lsra                    ; garde le chiffre des dizaines
        lsra
        lsra
        lsra
        pshs    a
        addb    ,s+             ; B = nombre total de dizaines
        tfr     b,a
        cmpa    #99
        bls     cv2
cv1     lda     #99
cv2     adda    startlv         ; + niveau choisi au depart
        cmpa    #99
        bls     cv3
        lda     #99
cv3     cmpa    level           ; plus grand que le niveau actuel ?
        bls     cv9             ; non : rien ne change
        sta     level           ; nouveau niveau !
        bsr     setspd          ; nouvelle vitesse
        ldx     #sfxlevel       ; petit jingle
        jmp     playseq
cv9     rts

* ----- setspd : vitesse = table de la Game Boy (en images par ligne)
setspd  lda     level
        cmpa    #20             ; au-dela du niveau 20...
        bls     ss1
        lda     #20             ; ...la vitesse ne change plus
ss1     ldx     #spdtab
        lda     a,x             ; A = spdtab[niveau]
        sta     speed
        rts

* ----- drawstats : met a jour tous les nombres des cadres
* score / niveau / lignes
drawstats lda   #CTEXT
        sta     tcol
        lda     #6              ; ligne 6
        sta     ny
        ldx     #score          ; score : 3 octets BCD
        ldb     #3
        lda     #30             ; colonne 30
        jsr     putbcd
        lda     #13             ; niveau : ligne 13
        sta     ny
        lda     level
        jsr     bin2bcd         ; converti en BCD
        sta     tmpb            ; dans une case temporaire
        ldx     #tmpb
        ldb     #1              ; 1 octet = 2 chiffres
        lda     #6              ; colonne 6
        jsr     putbcd
        lda     #13
        sta     ny
        ldx     #lines          ; lignes : 2 octets BCD
        ldb     #2
        lda     #30
        jsr     putbcd
        lda     #19             ; record, ligne 19
        sta     ny
        ldx     hisptr
        ldb     #3
        lda     #30
        jsr     putbcd
        lda     gtype           ; lettre du type (A ou B)
        adda    #65
        sta     chr
        lda     #9              ; a cote de "TYPE"
        ldb     #18
        jmp     putch

*----------------------------------------------------------------
* Comme sur Game Boy, on cache le puits pendant la pause (pas de triche !)
* pause : le puits est cache comme sur Game Boy
pause   clr     tnum            ; tuile vide
        lda     #CFIELD
        sta     tcol
        lda     #10             ; tout le puits
        sta     rw
        lda     #18
        sta     rh
        lda     #FLD
        ldb     #3
        jsr     fillrect
        ldx     #s_pause
        lda     #FLD+2          ; au milieu du puits
        ldb     #11
        jsr     text
pa1     jsr     vsync           ; attend...
        jsr     scan
        lda     edge
        bita    #K_STOP         ; STOP -> ecran titre
        lbne    title
        bita    #K_PAUSE        ; P de nouveau ?
        beq     pa1             ; non : on attend encore
        jsr     drawfield       ; reaffiche le puits...
        lda     piece           ; ...et la piece
        inca
        sta     tnum
        jmp     drawpc

*----------------------------------------------------------------
* ----- gover : rideau de briques du bas vers le haut, puis message
* fin de partie
gover   ldx     #sfxover        ; musique triste
        jsr     playseq
        lda     #8              ; tuile brique
        sta     tnum
        lda     #CBRICK
        sta     tcol
        lda     #20             ; en partant de la ligne 20
        sta     gy
go1     lda     #10             ; une ligne de 10 briques
        sta     rw
        lda     #1
        sta     rh
        lda     #FLD
        ldb     gy
        jsr     fillrect
        ldb     #2              ; 2 images entre chaque ligne
        jsr     waitf
        dec     gy              ; ligne du dessus
        lda     gy
        cmpa    #3              ; jusqu'a la ligne 3
        bhs     go1
        clr     tnum            ; deux zones vides pour les messages
        lda     #CFIELD
        sta     tcol
        lda     #10
        sta     rw
        lda     #4
        sta     rh
        lda     #FLD
        ldb     #7
        jsr     fillrect
        lda     #10
        sta     rw
        lda     #4
        sta     rh
        lda     #FLD
        ldb     #13
        jsr     fillrect
        ldx     #s_game
        lda     #FLD+3
        ldb     #8
        jsr     text
        ldx     #s_over
        lda     #FLD+3
        ldb     #9
        jsr     text
        ldx     #s_please
        lda     #FLD+2
        ldb     #14
        jsr     text
        ldx     #s_again
        lda     #FLD
        ldb     #15
        jsr     text
        jsr     updhi           ; enregistre le record si battu
go3     jsr     vsync           ; attend une touche :
        jsr     scan
        lda     edge
        bita    #K_STOP
        lbne    title           ; STOP -> titre
        bita    #K_DROP+K_ROTA  ; ENTREE ou ESPACE...
        beq     go3
        jmp     launch          ; ...-> la fusee decolle

* ----- updhi : si score > record, le record devient le score
* (comparaison de nombres BCD sur 3 octets, octet de poids fort d'abord)
* meilleur score du type en cours
updhi   ldx     hisptr          ; X = record du type joue
        ldd     score           ; 2 premiers octets du score
        cmpd    ,x              ; CMPD compare 16 bits
        bhi     uh2             ; plus grand : nouveau record
        blo     uh9             ; plus petit : rien
        lda     score+2         ; egaux : on compare le 3e octet
        cmpa    2,x
        bls     uh9
uh2     ldd     score           ; copie le score dans le record
        std     ,x
        lda     score+2
        sta     2,x
uh9     rts

* ----- bwin : type B termine
* type B reussi : 25 lignes faites
bwin    ldx     #sfxwin         ; fanfare
        jsr     playseq
        jsr     updhi           ; record
        clr     tnum            ; zone vide au milieu du puits
        lda     #CFIELD
        sta     tcol
        lda     #10
        sta     rw
        lda     #5
        sta     rh
        lda     #FLD
        ldb     #8
        jsr     fillrect
        lda     #CYEL           ; en jaune
        sta     tcol
        ldx     #s_bravo
        lda     #FLD+2
        ldb     #9
        jsr     text
        ldx     #s_25
        lda     #FLD
        ldb     #11
        jsr     text
        jmp     go3             ; meme attente qu'au game over

* ----- garbage : lignes de dechets au hasard (type B)
* lignes de dechets du type B
garbage ldx     #garbh          ; table des hauteurs 0,3,5,8,10,12
        ldb     bheight
        lda     b,x             ; A = nombre de lignes pour la hauteur choisie
        beq     gb9             ; 0 : rien a faire
        sta     gcnt2           ; compteur de lignes
        lda     #20             ; on part du bas (ligne 20)
        sta     grow
gb1     ldb     grow            ; D = ligne x 16
        clra
        lslb
        rola
        lslb
        rola
        lslb
        rola
        lslb
        rola
        ldx     #board+3
        leax    d,x             ; X = 1re case de la ligne
        lda     #10             ; 10 cases
        sta     fcnt
        clr     gcnt3           ; nombre de cases remplies
gb2     jsr     rnd             ; tirage
        cmpa    #150            ; environ 60 % de cases pleines
        bhs     gb3
        jsr     rnd             ; couleur au hasard...
        ldb     #7
        mul
        inca                    ; ...1 a 7
        sta     ,x
        inc     gcnt3
        bra     gb4
gb3     clr     ,x              ; case vide
gb4     leax    1,x             ; case suivante
        dec     fcnt
        bne     gb2
        lda     gcnt3           ; ligne entierement pleine ?
        cmpa    #10
        bne     gb5             ; non : ok
        jsr     rnd             ; oui : on vide une case au hasard
        ldb     #10
        mul
        leax    -10,x           ; revient au debut de la ligne
        clr     a,x             ; vide la case numero A (0..9)
        dec     gcnt3
gb5     ldx     #rowcnt         ; note le nombre de cases de la ligne
        ldb     grow
        lda     gcnt3
        sta     b,x
        dec     grow            ; ligne du dessus
        dec     gcnt2
        bne     gb1
gb9     rts

* La fusee est dessinee pixel par pixel (pas par cases) pour pouvoir
* monter en douceur. Elle fait 32 pixels (4 octets) de large ; pour
* la grande navette chaque pixel est double en largeur et hauteur.
*================================================================
*  DECOLLAGE DE LA NAVETTE (fin de partie)
*================================================================
* 4 tailles selon le score (comme sur Game Boy) :
*  < 20000 petite fusee, < 50000 fusee Energia, < 100000 navette, sinon grande navette x2
* entree : corps, flamme1, flamme2, echelle, colonne, col. tour, haut tour
tiers   fdb     rkpet,flS1,flS2  ; dessin du corps, flammes (2 images)
        fcb     1,18,17,14      ; echelle 1, colonne 18, tour en 17, haut de tour ligne 14
        fdb     rkene,flE1,flE2
        fcb     1,18,17,12
        fdb     rkbody,flame1,flame2
        fcb     1,18,17,12
        fdb     rkbody,flame1,flame2
        fcb     2,16,15,7

launch  ldx     #tiers          ; X = 1re entree du tableau
        lda     score           ; octet de poids fort du score (BCD)
        cmpa    #$10            ; >= 100000 ?
        bhs     lt4
        cmpa    #$05            ; >= 50000 ?
        bhs     lt3
        cmpa    #$02            ; >= 20000 ?
        bhs     lt2
        bra     lt1
lt4     leax    10,x            ; entree suivante (10 octets)
lt3     leax    10,x
lt2     leax    10,x
lt1     ldd     ,x              ; recopie l'entree choisie dans les variables
        std     rkspr
        ldd     2,x
        std     fl1p
        ldd     4,x
        std     fl2p
        lda     6,x
        sta     rkscl
        lda     7,x
        sta     rkxv
        lda     8,x
        sta     twc
        lda     9,x
        sta     twt
        ldd     #64             ; taille normale : 64 lignes de haut (56 corps + 8 flammes)...
        ldx     #112            ; ...et le haut de la fusee a la ligne 112
        tst     rkscl           ; (inutile : reste d'une version precedente)
        lda     rkscl
        cmpa    #2              ; grande navette ?
        bne     lt5
        ldd     #128            ; 128 lignes de haut
        ldx     #56             ; haut a la ligne 56
lt5     std     rkh
        stx     rky0
        lda     #CSKY           ; ciel bleu partout
        jsr     cls
        lda     #8              ; sol en briques (lignes 22 a 24)
        sta     tnum
        lda     #CBRICK
        sta     tcol
        lda     #40
        sta     rw
        lda     #3
        sta     rh
        clra
        ldb     #22
        jsr     fillrect
        lda     #CTOWER         ; pas de tir (tuile 19)
        sta     tcol
        lda     #19
        sta     tnum
        lda     #12
        sta     rw
        lda     #1
        sta     rh
        lda     #14
        ldb     #21
        jsr     fillrect
        lda     #18             ; tour de lancement (tuile 18)
        sta     tnum
        lda     #1
        sta     rw
        lda     #21             ; hauteur = 21 - ligne du haut
        suba    twt
        sta     rh
        lda     twc
        ldb     twt
        jsr     fillrect
* nuages
        lda     #CCLOUD         ; nuages blancs sur ciel
        sta     tcol
        ldx     #clouds         ; liste des nuages (colonne, ligne)
lcl     lda     ,x+
        cmpa    #$FF
        beq     lcl2
        ldb     ,x+
        pshs    x
        ldx     #22             ; (inutile : reste d'une version precedente)
        stx     tmpw
        sta     fx              ; colonne du nuage
        lda     #22             ; tuiles 22, 23, 24 = gauche, milieu, droite
lcl1    sta     tnum
        lda     fx
        jsr     drawtile
        inc     fx
        lda     tnum
        inca                    ; tuile suivante
        cmpa    #25
        bne     lcl1
        puls    x
        bra     lcl
lcl2    clr     lframe          ; compteur d'images pour les animations
        ldd     rky0            ; position de depart
        std     rky             ; rky = ligne du haut (en pixels)
        lslb                    ; rkyf = meme chose x 8 (1/8 de pixel de precision)
        rola
        lslb
        rola
        lslb
        rola
        std     rkyf
        ldx     #0              ; pas de flammes au repos
        stx     flmptr
        jsr     drawrk          ; dessine la fusee
        ldb     #50             ; 1 seconde d'attente
        jsr     lwait           ; (une touche permet de passer)
        lbne    title
* Mise a feu : 60 images de fumee et de grondement
* mise a feu
        lda     #60
        sta     lcnt
li1     jsr     vsync
        inc     lframe
        jsr     smoke           ; anime la fumee
        jsr     rumble          ; bruit du moteur
        jsr     lkey
        lbne    title
        dec     lcnt
        bne     li1
* Decollage : la vitesse rkv augmente, la fusee monte et on efface les
* lignes qu'elle laisse derriere elle.
* decollage
        ldd     #2              ; vitesse de depart (en 1/8 de pixel par image)
        std     rkv
lf1     jsr     vsync
        inc     lframe
        ldd     rky             ; ancien bas de la fusee
        addd    rkh
        std     lim
        ldd     rkyf            ; monte...
        subd    rkv             ; ...de rkv huitiemes de pixel
        std     rkyf
        asra                    ; divise par 8 (ASRA garde le signe : la fusee
        rorb                    ; peut avoir une position negative en sortant de l'ecran)
        asra
        rorb
        asra
        rorb
        std     rky             ; nouvelle ligne du haut
        ldx     fl1p            ; flamme 1...
        lda     lframe
        anda    #2              ; toutes les 2 images...
        beq     lf2
        ldx     fl2p            ; ...flamme 2 (effet de scintillement)
lf2     stx     flmptr
        jsr     drawrk          ; dessine la fusee
* effacer les lignes laissees sous la fusee
        ldd     rky             ; nouveau bas de la fusee
        addd    rkh
        std     curl
lc1     ldd     curl            ; efface de la...
        cmpd    lim             ; ...jusqu'a l'ancien bas
        bge     lc2             ; BGE : >= (signe)
        jsr     clrline
        ldd     curl
        addd    #1
        std     curl
        bra     lc1
lc2     lda     lframe          ; toutes les 2 images :
        anda    #1
        bne     lc3
        ldd     rkv             ; la vitesse augmente...
        cmpd    #64             ; ...jusqu'a 64 (8 pixels par image)
        bge     lc4
        addd    #1
        std     rkv
lc4     jsr     smoke           ; et on anime la fumee
lc3     jsr     rumble
        jsr     lkey
        lbne    title
        ldd     rky             ; la fusee est-elle sortie ?
        addd    rkh             ; (bas de la fusee > 0 : encore visible)
        bgt     lf1             ; BGT : > (signe)
        clr     PRB             ; silence
        ldb     #75             ; 1,5 seconde de ciel vide
        jsr     lwait
        jmp     title

* ----- drawrk : dessine le corps (56 lignes) puis les flammes (8)
* dessin de la fusee a la ligne rky (flmptr=0 : sans flammes)
drawrk  lda     PRA             ; memoire "forme" (on ne touche pas aux couleurs)
        ora     #1
        sta     PRA
        ldd     rky             ; ligne de depart
        std     curl
        ldu     rkspr           ; dessin du corps
        lda     #56             ; 56 lignes
        sta     rcnt
        bsr     rkrows
        ldu     flmptr          ; flammes ?
        beq     dr9             ; 0 = pas de flammes
        lda     #8              ; 8 lignes
        sta     rcnt
        bsr     rkrows
dr9     rts

* rowbuf recoit une ligne (8 octets) puis putrow l'ecrit a l'ecran.
* chaque ligne source (4 octets) est doublee en largeur et en hauteur
rkrows  lda     rkscl           ; echelle
        cmpa    #2
        beq     rkr2            ; double taille ?
* taille normale
        ldd     ,u              ; recopie les 4 octets de la ligne...
        std     rowbuf
        ldd     2,u
        std     rowbuf+2
        ldd     #0              ; ...et 4 octets vides a droite
        std     rowbuf+4
        std     rowbuf+6
        leau    4,u             ; ligne source suivante
        bsr     putrow          ; ecrit une fois
        dec     rcnt
        bne     rkrows
        rts
rkr2    ldx     #dbltab         ; table de doublement : 4 bits -> 8 bits
        ldy     #rowbuf
        lda     #4              ; 4 octets source
        sta     rbc
rk1     lda     ,u+             ; octet source
        tfr     a,b
        lsra                    ; 4 bits de gauche...
        lsra
        lsra
        lsra
        lda     a,x             ; ...doubles
        andb    #15             ; 4 bits de droite...
        ldb     b,x             ; ...doubles
        std     ,y++            ; 2 octets dans rowbuf
        dec     rbc
        bne     rk1
        bsr     putrow          ; ecrit la ligne...
        bsr     putrow          ; ...deux fois (hauteur doublee)
        dec     rcnt
        bne     rkrows
        rts

* ----- putrow : ecrit rowbuf a la ligne curl si elle est visible
putrow  ldd     curl
        bmi     pr2             ; au-dessus de l'ecran ?
        cmpd    #176            ; en dessous du sol (ligne 176) ?
        bge     pr2             ; on ne dessine pas
        pshs    x
        bsr     lineadr         ; X = adresse a l'ecran
        ldd     rowbuf          ; 8 octets = 64 pixels
        std     ,x
        ldd     rowbuf+2
        std     2,x
        ldd     rowbuf+4
        std     4,x
        ldd     rowbuf+6
        std     6,x
        puls    x
pr2     ldd     curl            ; ligne suivante
        addd    #1
        std     curl
        rts

* ligne*40 = ligne*8 + ligne*32 (decalages au lieu d'une multiplication)
* D = ligne -> X = adresse ecran de la fusee
lineadr lslb                    ; x2
        rola
        lslb
        rola
        lslb                    ; x8
        rola
        std     tmp8
        lslb                    ; x16
        rola
        lslb                    ; x32
        rola
        addd    tmp8            ; x32 + x8 = x40
        addb    rkxv            ; + colonne de la fusee
        adca    #0              ; (retenue)
        tfr     d,x
        rts

* ----- clrline : efface la ligne curl sous la fusee
* efface 4 octets de la ligne curl
clrline ldd     curl
        bmi     cr9             ; hors ecran : rien
        cmpd    #176
        bge     cr9
        lda     PRA             ; memoire "forme"
        ora     #1
        sta     PRA
        ldd     curl
        bsr     lineadr
        ldd     #0              ; 8 octets a 0
        std     ,x
        std     2,x
        std     4,x
        std     6,x
cr9     rts

* ----- smoke : nuages de fumee qui alternent entre 2 dessins
* fumee au pied de la fusee
smoke   lda     #CCLOUD
        sta     tcol
        ldx     #smoketab       ; liste des positions (colonne, ligne)
        clr     fi
sk1     lda     ,x+             ; colonne
        cmpa    #$FF
        beq     sk9
        ldb     lframe          ; image / 4...
        lsrb
        lsrb
        addb    fi              ; ...+ numero du nuage (voisins decales)
        andb    #1              ; pair ou impair...
        addb    #20             ; ...-> tuile 20 ou 21
        stb     tnum
        ldb     ,x+             ; ligne
        jsr     drawtile
        inc     fi
        bra     sk1
sk9     rts

* Bruit : le buzzer suit les bits du generateur aleatoire
* grondement au buzzer (~6 ms)
rumble  ldb     #45             ; 45 impulsions
ru1     lsr     seed            ; meme calcul que "rnd", un bit a la fois
        ror     seed+1
        bcc     ru2
        lda     seed
        eora    #$B4
        sta     seed
        lda     #1              ; bit a 1 : son
        bra     ru3
ru2     clra                    ; bit a 0 : silence
ru3     sta     PRB
        ldx     #6              ; petite attente
ru4     leax    -1,x
        bne     ru4
        decb
        bne     ru1
        clr     PRB
        rts

* ----- lkey : une touche pour passer la scene ?
* touche pour passer : Z=0 si ENTREE/ESPACE/STOP
lkey    jsr     scan
        lda     edge
        anda    #K_DROP+K_ROTA+K_STOP
        rts

* attendre B images (Z=0 si touche)
lwait   pshs    b
lw1     jsr     vsync
        bsr     lkey
        bne     lw2
        dec     ,s
        bne     lw1
lw2     puls    b,pc

clouds  fcb     4,4,30,6,5,10,$FF  ; nuages : colonne, ligne (fin = $FF)
smoketab fcb    12,21,13,21,14,21,15,21,16,21,17,21,18,21,19,21,20,21,21,21,22,21,23,21  ; fumee : colonne, ligne
        fcb     24,21,25,21,26,21,27,21,12,20,13,20,14,20,24,20,25,20,26,20,27,20,$FF

* Les touches du jeu : code (colonne*16 + ligne*2) , bit de "keys"
*================================================================
*  DONNEES
*================================================================
keytab  fcb     $52,K_LEFT      ; fleche gauche
        fcb     $32,K_RIGHT     ; fleche droite
        fcb     $42,K_DOWN      ; fleche bas
        fcb     $62,K_ROTA      ; fleche haut
        fcb     $40,K_ROTA      ; espace
        fcb     $50,K_ROTB      ; X
        fcb     $60,K_ROTB      ; W
        fcb     $68,K_DROP      ; ENTREE
        fcb     $38,K_PAUSE     ; P
        fcb     $6E,K_STOP      ; STOP
        fcb     $FF
* Adresse ecran du debut de chaque ligne de texte : ligne x 320

rowtab  fdb     0,320,640,960,1280,1600,1920,2240,2560,2880
        fdb     3200,3520,3840,4160,4480,4800,5120,5440,5760,6080
        fdb     6400,6720,7040,7360,7680
* Points par nombre de lignes (BCD) : 0, 40, 100, 300, 1200

ptstab  fcb     $00,$00,$00
        fcb     $00,$00,$40
        fcb     $00,$01,$00
        fcb     $00,$03,$00
        fcb     $00,$12,$00
* Textes (termines par 0)

s_sub   fcc     "CLONE GAME BOY - THOMSON MO6"
        fcb     0
s_top   fcc     "TOP"
        fcb     0
s_mtype fcc     "TYPE      <   >"
        fcb     0
s_mlev  fcc     "NIVEAU    <   >"
        fcb     0
s_mhaut fcc     "HAUTEUR   <   >"
        fcb     0
s_bravo fcc     "BRAVO !"
        fcb     0
s_25    fcc     "25 LIGNES"
        fcb     0
garbh   fcb     0,3,5,8,10,12   ; hauteurs du type B en lignes
NXC     equ     5               ; position du cadre NEXT : colonne...
NXR     equ     4               ; ...et ligne de la piece
* cadres : colonne, ligne, largeur, hauteur
boxtab  fcb     2,2,11,7
        fcb     2,10,11,5
        fcb     2,16,11,5
        fcb     27,2,11,7
        fcb     27,10,11,5
        fcb     27,16,11,5
        fcb     $FF
* libelles : colonne, ligne, texte
labtab  fcb     5,3
        fdb     s_next
        fcb     5,11
        fdb     s_level
        fcb     4,18
        fdb     s_type
        fcb     30,3
        fdb     s_score
        fcb     30,11
        fdb     s_lines
        fcb     31,17
        fdb     s_top
        fcb     $FF
s_type  fcc     "TYPE"
        fcb     0
bigcol  fcb     $81,$A1,$51,$71,$41,$61  ; couleurs des lettres T E T R I S
menutab fcb     $52,K_LEFT      ; au titre : ESPACE et ENTREE lancent la partie
        fcb     $32,K_RIGHT
        fcb     $42,K_DOWN
        fcb     $62,K_ROTA
        fcb     $40,K_DROP
        fcb     $68,K_DROP
        fcb     $6E,K_STOP
        fcb     $FF
help    fcc     "GAUCHE DROITE : DEPLACER"  ; aide (lignes successives, fin = double 0)
        fcb     0
        fcc     "BAS : DESCENDRE"
        fcb     0
        fcc     "HAUT, ESPACE : ROTATION A"
        fcb     0
        fcc     "X, W : ROTATION B"
        fcb     0
        fcc     "ENTREE : CHUTE DIRECTE"
        fcb     0
        fcc     "P : PAUSE  STOP : QUITTER"
        fcb     0,0
s_start fcc     "HAUT BAS : CHOIX    ENTREE : JOUER"
        fcb     0
s_score fcc     "SCORE"
        fcb     0
s_level fcc     "LEVEL"
        fcb     0
s_lines fcc     "LINES"
        fcb     0
s_next  fcc     "NEXT"
        fcb     0
s_pause fcc     "PAUSE"
        fcb     0
s_game  fcc     "GAME"
        fcb     0
s_over  fcc     "OVER"
        fcb     0
s_please fcc    "PLEASE"
        fcb     0
s_again fcc     "TRY AGAIN"
        fcb     0

*================================================================
*  TABLES GENEREES (par le petit programme Python gen.py)
*   gbpal    : palette de 16 couleurs, 2 octets par couleur :
*              (vert*16 + rouge) puis bleu, chaque composante 0..15
*   defpal   : palette d'origine du MO6 (remise en partant)
*   tiles    : motifs 8x8, 8 octets par tuile (1 octet = 1 ligne,
*              bit a 1 = pixel dessine dans la couleur de forme)
*   tilecol  : couleur de chaque ligne des tuiles 0 a 9
*   font     : police de caracteres, ASCII 32 (espace) a 95
*   bigfont  : grosses lettres T E T R I S (4 tuiles par lettre)
*   shapes   : 7 pieces x 4 rotations x 4 cases (ligne*16+colonne)
*   spdtab   : images par ligne de chute pour les niveaux 0 a 20
*   music, sfx... : notes = amplitude, demi-periode (2 octets),
*              nombre de periodes (2 octets) ; $FF = fin
*   dbltab   : doublement des pixels pour la grande navette
*   rkbody, rkpet, rkene, flame..., flS..., flE... : dessins des
*              fusees et de leurs flammes (4 octets par ligne)
*================================================================
gbpal
        fcb     $00,$00,$00,$02,$FF,$0F,$88,$08,$90,$0C,$9D,$00,$05,$0B,$80,$00
        fcb     $0B,$00,$10,$0D,$3E,$00,$05,$00,$01,$00,$52,$0D,$11,$01,$9B,$03
defpal
        fcb     $00,$10,$0F,$00,$F0,$00,$FF,$00,$00,$0F,$0F,$0F,$F0,$0F,$FF,$0F
        fcb     $77,$07,$3A,$03,$A3,$03,$AA,$03,$33,$0A,$3A,$0A,$E7,$0E,$7B,$00
tiles
        fcb     $80,$00,$00,$00,$00,$00,$00,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
        fcb     $FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
        fcb     $FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
        fcb     $FE,$FE,$FE,$FE,$FE,$FE,$FE,$00,$FE,$FE,$FE,$FE,$FE,$FE,$FE,$00
        fcb     $FF,$88,$88,$88,$FF,$22,$22,$22,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
        fcb     $3F,$7F,$E0,$C0,$C0,$C0,$C0,$C0,$FF,$FF,$00,$00,$00,$00,$00,$00
        fcb     $FC,$FE,$07,$03,$03,$03,$03,$03,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
        fcb     $03,$03,$03,$03,$03,$03,$03,$03,$C0,$C0,$C0,$C0,$C0,$E0,$7F,$3F
        fcb     $00,$00,$00,$00,$00,$00,$FF,$FF,$03,$03,$03,$03,$03,$07,$FE,$FC
        fcb     $FF,$C3,$A5,$99,$99,$A5,$C3,$FF,$FF,$FF,$24,$24,$24,$24,$24,$7E
        fcb     $00,$3C,$42,$81,$81,$81,$42,$3C,$00,$66,$99,$81,$42,$81,$99,$66
        fcb     $00,$00,$0E,$11,$20,$40,$80,$FF,$3C,$42,$81,$00,$00,$00,$00,$FF
        fcb     $00,$00,$70,$88,$04,$02,$01,$FF,$00,$00,$00,$00,$00,$00,$00,$00
tilecol
        fcb     $E1,$01,$01,$01,$01,$01,$01,$01,$20,$40,$40,$40,$40,$40,$4E,$00
        fcb     $20,$50,$50,$50,$50,$50,$5E,$00,$20,$60,$60,$60,$60,$60,$6E,$00
        fcb     $20,$70,$70,$70,$70,$70,$7E,$00,$20,$80,$80,$80,$80,$80,$8E,$00
        fcb     $20,$90,$90,$90,$90,$90,$9E,$00,$20,$A0,$A0,$A0,$A0,$A0,$AE,$00
        fcb     $CB,$CB,$CB,$CB,$CB,$CB,$CB,$CB,$21,$21,$21,$21,$21,$21,$21,$21
font
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$18,$18,$18,$18,$18,$00,$18,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$38,$18,$30,$00,$00,$00,$00,$7E,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$38,$38,$00,$06,$06,$0C,$18,$30,$60,$60,$00
        fcb     $3C,$66,$6E,$7E,$76,$66,$3C,$00,$18,$38,$18,$18,$18,$18,$3C,$00
        fcb     $3C,$66,$06,$0C,$18,$30,$7E,$00,$7E,$0C,$18,$0C,$06,$66,$3C,$00
        fcb     $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00,$7E,$60,$7C,$06,$06,$66,$3C,$00
        fcb     $1C,$30,$60,$7C,$66,$66,$3C,$00,$7E,$06,$0C,$18,$30,$30,$30,$00
        fcb     $3C,$66,$66,$3C,$66,$66,$3C,$00,$3C,$66,$66,$3E,$06,$0C,$38,$00
        fcb     $00,$38,$38,$00,$38,$38,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $0C,$18,$30,$60,$30,$18,$0C,$00,$00,$00,$7E,$00,$7E,$00,$00,$00
        fcb     $30,$18,$0C,$06,$0C,$18,$30,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$3C,$66,$66,$7E,$66,$66,$66,$00
        fcb     $7C,$66,$66,$7C,$66,$66,$7C,$00,$3C,$66,$60,$60,$60,$66,$3C,$00
        fcb     $7C,$66,$66,$66,$66,$66,$7C,$00,$7E,$60,$60,$7C,$60,$60,$7E,$00
        fcb     $7E,$60,$60,$7C,$60,$60,$60,$00,$3C,$66,$60,$7E,$66,$66,$3E,$00
        fcb     $66,$66,$66,$7E,$66,$66,$66,$00,$3C,$18,$18,$18,$18,$18,$3C,$00
        fcb     $1E,$0C,$0C,$0C,$6C,$6C,$38,$00,$66,$6C,$78,$70,$78,$6C,$66,$00
        fcb     $60,$60,$60,$60,$60,$60,$7E,$00,$66,$7E,$7E,$7E,$66,$66,$66,$00
        fcb     $66,$76,$7E,$6E,$66,$66,$66,$00,$3C,$66,$66,$66,$66,$66,$3C,$00
        fcb     $7C,$66,$66,$7C,$60,$60,$60,$00,$3C,$66,$66,$66,$7E,$6C,$3E,$00
        fcb     $7C,$66,$66,$7C,$78,$6C,$66,$00,$3E,$60,$60,$3C,$06,$06,$7C,$00
        fcb     $7E,$18,$18,$18,$18,$18,$18,$00,$66,$66,$66,$66,$66,$66,$3C,$00
        fcb     $66,$66,$66,$66,$66,$3C,$18,$00,$66,$66,$66,$7E,$7E,$7E,$3C,$00
        fcb     $66,$66,$3C,$18,$3C,$66,$66,$00,$66,$66,$3C,$18,$18,$18,$18,$00
        fcb     $7E,$06,$0C,$18,$30,$60,$7E,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
bigfont
        fcb     $3F,$3F,$03,$03,$03,$03,$03,$03,$FC,$FC,$C0,$C0,$C0,$C0,$C0,$C0
        fcb     $03,$03,$03,$03,$03,$03,$00,$00,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00
        fcb     $3F,$3F,$3C,$3C,$3C,$3C,$3F,$3F,$FC,$FC,$00,$00,$00,$00,$F0,$F0
        fcb     $3C,$3C,$3C,$3C,$3F,$3F,$00,$00,$00,$00,$00,$00,$FC,$FC,$00,$00
        fcb     $3F,$3F,$03,$03,$03,$03,$03,$03,$FC,$FC,$C0,$C0,$C0,$C0,$C0,$C0
        fcb     $03,$03,$03,$03,$03,$03,$00,$00,$C0,$C0,$C0,$C0,$C0,$C0,$00,$00
        fcb     $3F,$3F,$3C,$3C,$3C,$3C,$3F,$3F,$F0,$F0,$3C,$3C,$3C,$3C,$F0,$F0
        fcb     $3F,$3F,$3C,$3C,$3C,$3C,$00,$00,$C0,$C0,$F0,$F0,$3C,$3C,$00,$00
        fcb     $0F,$0F,$03,$03,$03,$03,$03,$03,$F0,$F0,$C0,$C0,$C0,$C0,$C0,$C0
        fcb     $03,$03,$03,$03,$0F,$0F,$00,$00,$C0,$C0,$C0,$C0,$F0,$F0,$00,$00
        fcb     $0F,$0F,$3C,$3C,$3C,$3C,$0F,$0F,$FC,$FC,$00,$00,$00,$00,$F0,$F0
        fcb     $00,$00,$00,$00,$3F,$3F,$00,$00,$3C,$3C,$3C,$3C,$F0,$F0,$00,$00
shapes
        fcb     $10,$11,$12,$13,$02,$12,$22,$32,$10,$11,$12,$13,$02,$12,$22,$32
        fcb     $11,$12,$21,$22,$11,$12,$21,$22,$11,$12,$21,$22,$11,$12,$21,$22
        fcb     $10,$11,$12,$21,$01,$11,$21,$10,$12,$11,$10,$01,$21,$11,$01,$12
        fcb     $11,$12,$20,$21,$11,$21,$00,$10,$11,$12,$20,$21,$11,$21,$00,$10
        fcb     $10,$11,$21,$22,$01,$11,$10,$20,$10,$11,$21,$22,$01,$11,$10,$20
        fcb     $10,$11,$12,$22,$01,$11,$21,$20,$12,$11,$10,$00,$21,$11,$01,$02
        fcb     $10,$11,$12,$20,$01,$11,$21,$00,$12,$11,$10,$02,$21,$11,$01,$22
spdtab
        fcb     $2C,$29,$26,$22,$1F,$1C,$17,$12,$0E,$09,$08,$08,$07,$06,$05,$05
        fcb     $04,$04,$03,$03,$02
music
        fcb     $01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01
        fcb     $00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00
        fcb     $5D,$00,$1A,$01,$00,$5D,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$7C
        fcb     $00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00
        fcb     $02,$00,$00,$3C,$00,$19,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15
        fcb     $01,$00,$75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00,$19,$01
        fcb     $00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00
        fcb     $68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68
        fcb     $00,$18,$01,$00,$68,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$75,$00
        fcb     $15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$03
        fcb     $00,$00,$3C,$00,$19,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01
        fcb     $00,$7C,$00,$14,$01,$00,$7C,$00,$02,$00,$00,$3C,$00,$19,$01,$00
        fcb     $8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C
        fcb     $00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00
        fcb     $12,$01,$00,$8C,$00,$02,$00,$00,$3C,$00,$19,$01,$00,$8C,$00,$12
        fcb     $01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$02,$00
        fcb     $00,$3C,$00,$19,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00
        fcb     $75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$5D
        fcb     $00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00
        fcb     $1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A
        fcb     $01,$00,$5D,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$68,$00,$18,$01
        fcb     $00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$03,$00,$00
        fcb     $3C,$00,$19,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75
        fcb     $00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$7C,$00
        fcb     $14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14
        fcb     $01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01
        fcb     $00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00
        fcb     $7C,$00,$14,$01,$00,$7C,$00,$02,$00,$00,$3C,$00,$19,$01,$00,$75
        fcb     $00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00
        fcb     $03,$00,$00,$3C,$00,$19,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18
        fcb     $01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01
        fcb     $00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$03,$00,$00
        fcb     $3C,$00,$19,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D
        fcb     $00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00
        fcb     $1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$03,$00,$00,$3C,$00,$19
        fcb     $01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01
        fcb     $00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00
        fcb     $75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$8C
        fcb     $00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00
        fcb     $12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12
        fcb     $01,$00,$8C,$00,$02,$00,$00,$3C,$00,$19,$01,$00,$8C,$00,$12,$01
        fcb     $00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00
        fcb     $8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C
        fcb     $00,$02,$00,$00,$3C,$00,$19,$00,$00,$3C,$00,$28,$00,$00,$3C,$00
        fcb     $28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28
        fcb     $00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$14,$00
        fcb     $00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00
        fcb     $3C,$00,$1E,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68
        fcb     $00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00
        fcb     $18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$03,$00,$00,$3C,$00,$19
        fcb     $01,$00,$57,$00,$1C,$01,$00,$57,$00,$1C,$01,$00,$57,$00,$1C,$01
        fcb     $00,$57,$00,$04,$00,$00,$3C,$00,$19,$01,$00,$45,$00,$23,$01,$00
        fcb     $45,$00,$23,$01,$00,$45,$00,$23,$01,$00,$45,$00,$23,$01,$00,$45
        fcb     $00,$23,$01,$00,$45,$00,$23,$01,$00,$45,$00,$23,$01,$00,$45,$00
        fcb     $04,$00,$00,$3C,$00,$19,$01,$00,$4E,$00,$1F,$01,$00,$4E,$00,$1F
        fcb     $01,$00,$4E,$00,$1F,$01,$00,$4E,$00,$04,$00,$00,$3C,$00,$19,$01
        fcb     $00,$57,$00,$1C,$01,$00,$57,$00,$1C,$01,$00,$57,$00,$1C,$01,$00
        fcb     $57,$00,$04,$00,$00,$3C,$00,$19,$01,$00,$5D,$00,$1A,$01,$00,$5D
        fcb     $00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00
        fcb     $1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A
        fcb     $01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01
        fcb     $00,$5D,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$75,$00,$15,$01,$00
        fcb     $75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C
        fcb     $00,$19,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00
        fcb     $1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A
        fcb     $01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$03,$00,$00,$3C,$00,$19,$01
        fcb     $00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00
        fcb     $68,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$75,$00,$15,$01,$00,$75
        fcb     $00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00
        fcb     $19,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14
        fcb     $01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01
        fcb     $00,$7C,$00,$14,$01,$00,$7C,$00,$02,$00,$00,$3C,$00,$19,$01,$00
        fcb     $7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C,$00,$14,$01,$00,$7C
        fcb     $00,$02,$00,$00,$3C,$00,$19,$01,$00,$75,$00,$15,$01,$00,$75,$00
        fcb     $15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$03,$00,$00,$3C,$00,$19
        fcb     $01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01
        fcb     $00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00,$68,$00,$18,$01,$00
        fcb     $68,$00,$18,$01,$00,$68,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$5D
        fcb     $00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00
        fcb     $1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A,$01,$00,$5D,$00,$1A
        fcb     $01,$00,$5D,$00,$03,$00,$00,$3C,$00,$19,$01,$00,$75,$00,$15,$01
        fcb     $00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00
        fcb     $75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75,$00,$15,$01,$00,$75
        fcb     $00,$03,$00,$00,$3C,$00,$19,$01,$00,$8C,$00,$12,$01,$00,$8C,$00
        fcb     $12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12
        fcb     $01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$02,$00
        fcb     $00,$3C,$00,$19,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00
        fcb     $8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C
        fcb     $00,$12,$01,$00,$8C,$00,$12,$01,$00,$8C,$00,$02,$00,$00,$3C,$00
        fcb     $19,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28
        fcb     $00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00,$00,$3C,$00,$28,$00
        fcb     $00,$3C,$00,$28,$00,$00,$3C,$00,$14,$FF
sfxrot
        fcb     $01,$00,$16,$00,$15,$FF
sfxlock
        fcb     $01,$01,$DC,$00,$03,$FF
sfxline
        fcb     $01,$00,$3A,$00,$2A,$01,$00,$2D,$00,$35,$01,$00,$26,$00,$3E,$01
        fcb     $00,$1C,$00,$7C,$FF
sfxtetr
        fcb     $01,$00,$3A,$00,$2F,$01,$00,$2D,$00,$3C,$01,$00,$26,$00,$46,$01
        fcb     $00,$1C,$00,$5D,$01,$00,$26,$00,$46,$01,$00,$1C,$00,$5D,$01,$00
        fcb     $16,$00,$E9,$FF
sfxlevel
        fcb     $01,$00,$4E,$00,$37,$01,$00,$3A,$00,$49,$01,$00,$26,$00,$9C,$FF
sfxwin
        fcb     $01,$00,$75,$00,$2A,$00,$00,$3C,$00,$14,$01,$00,$5D,$00,$35,$00
        fcb     $00,$3C,$00,$14,$01,$00,$4E,$00,$3E,$00,$00,$3C,$00,$14,$01,$00
        fcb     $3A,$00,$BB,$00,$00,$3C,$00,$14,$01,$00,$4E,$00,$3E,$00,$00,$3C
        fcb     $00,$14,$01,$00,$3A,$01,$8B,$00,$00,$3C,$00,$14,$FF
sfxover
        fcb     $01,$00,$9D,$00,$2F,$01,$00,$B1,$00,$2A,$01,$00,$BB,$00,$28,$01
        fcb     $00,$D3,$00,$23,$01,$00,$ED,$00,$4E,$FF
dbltab
        fcb     $00,$03,$0C,$0F,$30,$33,$3C,$3F,$C0,$C3,$CC,$CF,$F0,$F3,$FC,$FF
rkbody
        fcb     $00,$07,$E0,$00,$00,$04,$20,$00,$00,$08,$10,$00,$00,$08,$10,$00
        fcb     $00,$10,$08,$00,$00,$10,$08,$00,$00,$10,$08,$00,$00,$10,$08,$00
        fcb     $00,$1F,$F8,$00,$00,$10,$08,$00,$02,$10,$08,$00,$03,$10,$08,$00
        fcb     $05,$11,$88,$00,$04,$90,$08,$00,$08,$90,$08,$40,$08,$90,$08,$A0
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$0F,$91,$89,$10,$08,$90,$09,$E8
        fcb     $08,$F0,$0A,$E8,$08,$90,$0A,$E8,$08,$90,$0A,$08,$08,$90,$0A,$08
        fcb     $08,$91,$8E,$08,$08,$90,$0A,$08,$08,$90,$0A,$08,$08,$90,$0A,$08
        fcb     $08,$90,$0A,$08,$08,$90,$0A,$08,$08,$91,$8A,$08,$08,$90,$0A,$08
        fcb     $08,$90,$0A,$08,$08,$90,$0B,$08,$08,$90,$0B,$09,$08,$90,$0A,$8B
        fcb     $08,$91,$8A,$4B,$08,$90,$0A,$4F,$08,$90,$0A,$2F,$08,$90,$0A,$1F
        fcb     $08,$90,$0A,$9F,$08,$90,$0A,$4F,$08,$90,$0E,$4F,$08,$90,$0A,$2C
        fcb     $08,$9F,$FA,$1A,$08,$90,$0A,$12,$08,$F0,$0B,$FF,$08,$90,$09,$F0
        fcb     $08,$90,$09,$F0,$08,$90,$0B,$F8,$0F,$9F,$FB,$F8,$0F,$8F,$F0,$00
        fcb     $0F,$8F,$F0,$00,$1F,$DF,$F8,$00,$1F,$DF,$F8,$00,$00,$1F,$F8,$00
flame1
        fcb     $1F,$DF,$F8,$00,$10,$91,$88,$00,$08,$88,$10,$00,$09,$08,$10,$00
        fcb     $07,$04,$20,$00,$00,$04,$20,$00,$00,$02,$C0,$00,$00,$01,$00,$00
flame2
        fcb     $0F,$8F,$F0,$00,$08,$89,$90,$00,$08,$84,$20,$00,$08,$84,$20,$00
        fcb     $0A,$84,$20,$00,$0D,$85,$20,$00,$08,$82,$C0,$00,$00,$02,$40,$00
rkpet
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        fcb     $00,$01,$80,$00,$00,$01,$80,$00,$00,$02,$40,$00,$00,$02,$40,$00
        fcb     $00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$04,$20,$00,$00,$04,$20,$00,$00,$05,$A0,$00,$00,$05,$A0,$00
        fcb     $00,$05,$A0,$00,$00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$07,$E0,$00,$00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$0C,$30,$00,$00,$0C,$30,$00,$00,$1C,$38,$00,$00,$1C,$38,$00
        fcb     $00,$3C,$3C,$00,$00,$3C,$3C,$00,$00,$3F,$FC,$00,$00,$27,$E4,$00
        fcb     $00,$07,$E0,$00,$00,$0F,$F0,$00,$00,$0F,$F0,$00,$00,$0F,$F0,$00
flS1
        fcb     $00,$1F,$F8,$00,$00,$11,$88,$00,$00,$08,$10,$00,$00,$08,$10,$00
        fcb     $00,$04,$20,$00,$00,$04,$20,$00,$00,$02,$C0,$00,$00,$01,$00,$00
flS2
        fcb     $00,$0F,$F0,$00,$00,$09,$90,$00,$00,$04,$20,$00,$00,$04,$20,$00
        fcb     $00,$04,$20,$00,$00,$05,$20,$00,$00,$02,$C0,$00,$00,$02,$40,$00
rkene
        fcb     $00,$07,$E0,$00,$00,$04,$20,$00,$00,$08,$10,$00,$00,$08,$10,$00
        fcb     $00,$10,$08,$00,$00,$10,$08,$00,$00,$10,$08,$00,$00,$10,$08,$00
        fcb     $00,$1F,$F8,$00,$00,$10,$08,$00,$02,$10,$08,$40,$03,$10,$08,$60
        fcb     $05,$11,$88,$A0,$04,$90,$08,$90,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$0F,$91,$89,$F0,$08,$90,$09,$10
        fcb     $08,$F0,$0F,$10,$08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$91,$89,$10,$08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$08,$91,$89,$10,$08,$90,$09,$10
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$91,$89,$10,$08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10,$08,$90,$09,$10
        fcb     $08,$9F,$F9,$10,$08,$90,$09,$10,$08,$F0,$0F,$10,$08,$90,$09,$10
        fcb     $08,$90,$09,$10,$08,$90,$09,$10,$0F,$9F,$F9,$F0,$0F,$8F,$F1,$F0
        fcb     $0F,$8F,$F1,$F0,$1F,$DF,$FB,$F8,$1F,$DF,$FB,$F8,$00,$1F,$F8,$00
flE1
        fcb     $1F,$DF,$FB,$F8,$10,$91,$8A,$10,$08,$88,$11,$10,$09,$08,$11,$20
        fcb     $07,$04,$20,$E0,$00,$04,$20,$00,$00,$02,$C0,$00,$00,$01,$00,$00
flE2
        fcb     $0F,$8F,$F1,$F0,$08,$89,$91,$10,$08,$84,$21,$10,$08,$84,$21,$10
        fcb     $0A,$84,$21,$50,$0D,$85,$21,$B0,$08,$82,$C1,$10,$00,$02,$40,$00

* rmb = reserve des octets (pas de valeur de depart)
*================================================================
*  VARIABLES
*================================================================
savesp  rmb     2               ; pile du BASIC au demarrage
seed    rmb     2               ; etat du generateur aleatoire
keys    rmb     1               ; touches enfoncees
prevk   rmb     1               ; touches de l'image precedente
edge    rmb     1               ; touches nouvellement enfoncees
tcol    rmb     1               ; couleur courante (forme*16 + fond)
tnum    rmb     1               ; numero de tuile a dessiner
chr     rmb     1               ; caractere a dessiner
tcx     rmb     1               ; position du texte en cours
tcy     rmb     1
fx      rmb     1               ; variables de travail des dessins
fx0     rmb     1
fy      rmb     1
fi      rmb     1
fcnt    rmb     1
rw      rmb     1
rh      rmb     1
tl      rmb     1               ; tuiles gauche/milieu/droite d'un cadre
tm      rmb     1
tr      rmb     1
bx      rmb     1               ; position et taille d'un cadre
by      rmb     1
bw      rmb     1
bh      rmb     1
bcnt    rmb     1
nx      rmb     1               ; variables d'affichage des nombres
ny      rmb     1
ncnt    rmb     1
nz      rmb     1
nlast   rmb     1
nbyte   rmb     1
tamp    rmb     1               ; son : amplitude et demi-periode
thalf   rmb     2
startlv rmb     1               ; niveau choisi au titre
score   rmb     3               ; score (6 chiffres BCD)
lines   rmb     2               ; lignes (4 chiffres BCD)
level   rmb     1               ; niveau actuel
speed   rmb     1               ; images par ligne de chute
gcnt    rmb     1               ; compteur de gravite
dascnt  rmb     1               ; compteur de repetition gauche/droite
sdcnt   rmb     1               ; compteur de descente rapide
downok  rmb     1               ; descente rapide autorisee
dropcnt rmb     1               ; lignes descendues vite (= points)
topout  rmb     1               ; 1 = perdu
piece   rmb     1               ; piece courante (0..6 : I O T S Z J L)
nextp   rmb     1               ; piece suivante
rot     rmb     1               ; rotation courante (0..3)
nrot    rmb     1
pos     rmb     2               ; position dans le plateau (ligne*16 + colonne)
npos    rmb     2
shptr   rmb     2               ; pointeur vers les 4 cases de la forme
nsh     rmb     2
dxv     rmb     2
pcnt    rmb     1
ltile   rmb     1
tmpw    rmb     2
tmpb    rmb     1
nfull   rmb     1
fullrows rmb    4               ; lignes pleines trouvees
r0      rmb     1
rrow    rmb     1
fcount  rmb     1
cnt     rmb     1
gy      rmb     1
lframe  rmb     1
lcnt    rmb     1
rcnt    rmb     1
rky     rmb     2               ; variables de la scene de la fusee
rkyf    rmb     2
rkv     rmb     2
lim     rmb     2
curl    rmb     2
flmptr  rmb     2
tmp8    rmb     2
rkspr   rmb     2
fl1p    rmb     2
fl2p    rmb     2
rkscl   rmb     1
rkxv    rmb     1
twc     rmb     1
twt     rmb     1
rkh     rmb     2
rky0    rmb     2
hisptr  rmb     2               ; pointeur vers hisA ou hisB
ktab    rmb     2               ; table de touches en service
gtype   rmb     1               ; 0 = type A, 1 = type B
bheight rmb     1               ; hauteur des dechets (0..5)
msel    rmb     1               ; ligne choisie dans le menu
blines  rmb     1               ; lignes restantes en type B
bdone   rmb     1               ; 1 = type B gagne
gcnt2   rmb     1
gcnt3   rmb     1
grow    rmb     1
rowbuf  rmb     8               ; une ligne de la fusee
rbc     rmb     1
rowcnt  rmb     24              ; nombre de cases par ligne du plateau
board   rmb     384             ; le plateau : 24 lignes x 16 colonnes
endprog                         ; fin du programme
