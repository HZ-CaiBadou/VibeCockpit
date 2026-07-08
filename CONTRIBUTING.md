# Contributing to VibeCockpit

Thanks for your interest in improving VibeCockpit.

## Development

1. Fork or clone the repository:

   ```sh
   git clone https://github.com/HZ-CaiBadou/VibeCockpit.git
   cd VibeCockpit
   ```

2. Open the app project:

   ```sh
   open VibeCockpit.xcodeproj
   ```

3. Run the lightweight checks before submitting changes:

   ```sh
   swift run VibeCockpitCoreChecks
   ```

## Security

Do not commit:

- Session keys, refresh tokens, access tokens, cookies, or `.env` files
- Signing certificates, private keys, provisioning profiles, or exported keychains
- `build/`, `dist/`, `.build/`, `.agents/`, `.app`, `.dmg`, or `.zip` outputs

## Pull Requests

- Keep changes focused.
- Describe the user-facing behavior changed.
- Include verification steps or screenshots for UI changes.
- Update README or localized strings when changing visible text.

## License

By contributing, you agree that your contribution is licensed under the MIT License.
