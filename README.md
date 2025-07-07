# Discourse Phone Field Bonus

A Discourse plugin that awards gamification points when users fill in their phone number field, integrating seamlessly with the Discourse Gamification plugin.

## Installation

Add the plugin repository to your app.yml file:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/yourusername/discourse-phone-field-bonus.git
```

Rebuild your Discourse container:

```bash
cd /var/discourse
./launcher rebuild app
```

Enable the plugin in Admin → Plugins → Settings:
- Check "phone field bonus enabled"
- Configure points awarded for completing phone field (default: 10)
- Set the phone number user field ID (default: 1)

## Usage

Once installed, users will automatically receive 10 gamification points when they fill in their phone number in their user profile. The plugin prevents duplicate point awards and includes basic phone number validation. Requires the Discourse Gamification plugin to be installed and enabled. 