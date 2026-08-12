# adicionar o arquivo da aplicacao no Bucket

# listar os Buckets existentes e filtra pelo nome
aws s3api list-buckets `
--query "Buckets[].Name"

# realizar o upload do objeto
aws s3api put-object `
--bucket jvm-status-ops-01a `
--key status.war `
--body .\status.war

# realizar a exclusao do objeto - se necessario
aws s3api delete-object `
--bucket jvm-status-ops-01a `
--key status.war