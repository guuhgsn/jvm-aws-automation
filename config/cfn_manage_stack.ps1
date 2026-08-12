# criar a Stack no CFN usando as permissoes necessarias para criar recursos
aws cloudformation create-stack `
--stack-name JVMStatusLab `
--template-body file://infra/jvm_infrastructure.yaml `
--capabilities CAPABILITY_NAMED_IAM

# atualizar a Stack no CFN - se necessario
aws cloudformation update-stack `
--stack-name JVMStatusLab `
--template-body file://infra/jvm_infrastructure.yaml `
--capabilities CAPABILITY_NAMED_IAM