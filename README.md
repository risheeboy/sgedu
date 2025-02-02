
## Dev environment setup

Prerequisites:

- [Flutter](https://docs.flutter.dev/get-started/install)
- [Firebase CLI](https://firebase.google.com/docs/cli#setup_update_cli)

Run these commands to verify prerequisites setup:

```bash
flutter doctor
firebase --version
node --version
```

### First Time Local Setup 

1. Clone the repository:
```bash
git clone https://github.com/ashishawasthi/storewl.git
cd sgedu
mv lib/firebase_options.dart.example lib/firebase_options.dart # change the values
```

2. Install Flutter dependencies:
```bash
flutter pub get
```

3. Install firebase function dependencies:
```bash
cd functions
npm install
cd ..
```

### Start Development Server

Launch the local web server:
```bash
flutter run -d chrome
```

## Deployment

### Full Deployment
Deploy all components (Functions, Hosting, Firestore rules):
```bash
flutter build web
firebase deploy
```

### Partial Deployments

Deploy specific components:

```bash
# Web app only
flutter build web
firebase deploy --only hosting

# Firebase node functions with 5 retries on Mac
for i in {1..5}; do firebase deploy --only functions && break; done

# Firebase node functions with 5 retries on Windows powershell
for($i=1; $i -le 5; $i++){ firebase deploy --only functions; if($LASTEXITCODE -eq 0){ break } }

# Firestore rules only
firebase deploy --only firestore:rules

# Firestore indexes only
firebase deploy --only firestore:indexes
```

## Firebase cloud project setup

Only required for new Firebase project setup or configuration changes.

### Initial Firebase Configuration

```bash
firebase login
firebase init
```

