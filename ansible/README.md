
# k8s.cloud setup

<br>

documentation tbd --

<br>

## Misc
### encrypt main password vault
```shell
ansible-vault encrypt /usr/share/automation/git/INFRA-Security/ansible/secrets.yml
```

### encrypt all certificates with
```shell
find /usr/share/automation/secrets/logstash -type f \( -name "*.crt" -o -name "*.pem" \)  -exec sh -c '
  for file; do
    output_path="/usr/share/automation/git/INFRA-Security/ansible/roles/logstash/files/$(basename $file)"
    ansible-vault encrypt "$file" --output "$output_path"
  done
' sh {} +
```
