# Tessel

Une petite app iOS SwiftUI pour créer une grille à partir des photos de la
pellicule, puis l'exporter vers Instagram ou toute autre app via la feuille de
partage iOS.

## Lancer l'app

1. Ouvrir `Tessel.xcodeproj` dans Xcode 16 ou plus récent.
2. Choisir une équipe de signature dans **Signing & Capabilities**.
3. Sélectionner un simulateur iPhone ou un iPhone physique.
4. Lancer avec `⌘R`.

Le déploiement minimum est iOS 17. La sélection de photos utilise le sélecteur
système : l'app n'a pas besoin d'un accès global à la photothèque.

## Fonctionnalités

- sélection ordonnée de 1 à 9 photos ;
- formats Instagram carré (1:1) et portrait (4:5) ;
- permutation de deux photos par toucher ;
- réglage de l'espacement, des coins et du fond ;
- export en 1080 px et partage avec Instagram, Messages, AirDrop, etc. ;
- enregistrement automatique des cadres, listés en mosaïque sur l'accueil
  pour les rouvrir et les modifier (appui long pour supprimer).

