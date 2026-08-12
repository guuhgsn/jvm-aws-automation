# JVMStatusLab - Hard-Restart Automation for JVMs with AWS Systems Manager

*Infrastructure as code, remote execution via SSM, and automatic notifications, a hands-on cloud automation lab, built to run within the Free Tier / AWS Academy Learner Lab (VocLabs).*

## Architecture Diagram

<p align="center">
  <img src="./images/diagram.png" alt="Architecture Diagram" width="99%">
</p>

## Table of Contents

- [About the Project](#about-the-project)
- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Technologies Used](#technologies-used)
- [Infrastructure Components](#infrastructure-components)
- [Prerequisites](#prerequisites)
- [Step-by-Step Guide](#step-by-step-guide)
- [Cleaning Up Resources](#cleaning-up-resources)
- [Troubleshooting](#troubleshooting)
- [Limitations and Possible Improvements](#limitations-and-possible-improvements)

## About the Project

This is a lab project focused on hands-on understanding of basic cloud automation and operations concepts, also known as ITOps or CloudOps. The simulated scenario is fairly common in environments running Java applications: when an application instance (JVM) stops responding, someone needs to restart it, ideally quickly, consistently, and with the right team getting notified about what happened.

Instead of relying on manual access to each server, the project uses **AWS Systems Manager** to run that recovery remotely, without SSH and without requiring advanced technical knowledge from whoever happens to be available at the time, and **Amazon SNS** to automatically notify when the action is executed.

The whole environment was designed to fit within Free Tier limits and labs like the AWS Academy Learner Lab, so some architectural decisions, like using an existing Role instead of creating a new one, make more sense when read with that in mind, and are explained throughout the text.

## Architecture Overview

Broadly, the flow works like this:

1. A single EC2 instance hosts **4 independent Apache Tomcat processes** (`usprd01a`, `usprd02b`, `usprd03c`, `usprd04d`), each on a different local port.
2. An **NGINX** in front of these processes acts as a reverse proxy / load balancer (round-robin), exposing everything on port 80.
3. Each JVM serves the same status application (`ROOT.war`), which displays identifying information about the process that answered the request.
4. The automation runbook (**SSM Automation Document**) can be triggered manually, using the AWS Management Console or the AWS CLI, where the user provides the server and the target JVM as parameters. It locates the process, forces it to stop, restarts the application, and publishes a notification to **Amazon SNS**, forwarded by email.
5. The application artifact (`status.war`) is stored in an **S3 Bucket**, from which it's downloaded while configuring each JVM.

> 💡 For Free Tier or lab environments, where the number of simultaneous instances tends to be quite limited and each additional instance eats into more of your quota, or session time, in VocLabs' case. Running multiple Apache Tomcat processes on different ports, behind an NGINX acting as a load balancer, makes it possible to simulate an application "cluster" while spending a single `t3.micro`. In a real environment, each JVM would tend to live on its own instance, or container, behind a managed Load Balancer (ALB).

## Project Structure

```
📁 JVM-AWS-AUTOMATION/
├── 📁 config/
│   ├── cfn_manage_stack.ps1      # Local script (PowerShell) — creates/updates the CloudFormation Stack
│   ├── jvms_config.sh            # Script run on the EC2 instance — installs/configures Tomcat, the JVMs, and NGINX
│   └── s3_manage_object.ps1      # Local script (PowerShell) — uploads/removes objects in S3
├── 📁 infra/
│   └── jvm_infrastructure.yaml   # CloudFormation template — defines the entire AWS infrastructure
├── 📁 status/
│   ├── 📁 WEB-INF/
│   │   └── web.xml               # Application deployment descriptor (WEB-INF)
│   └── index.jsp                 # JSP page that displays each JVM's status
└── README.md                     # This file
```

## Technologies Used

| Category | Technology |
|---|---|
| Infrastructure as Code (IaC) | AWS CloudFormation |
| Compute | Amazon EC2 |
| Operating System | Amazon Linux 2023 |
| Networking | Amazon VPC |
| Automation / Remote Execution | AWS Systems Manager (Automation + Session Manager) |
| Notifications | Amazon SNS |
| Storage | Amazon S3 |
| Identity and Access | AWS IAM (Instance Profile) |
| Middleware | Apache Tomcat 9 |
| Runtime | Amazon Corretto (Java 17) + JSP |
| Proxy / Load Balancing | NGINX |
| Local Automation | Windows PowerShell + AWS CLI |

## Infrastructure Components

The infrastructure is defined entirely in `jvm_infrastructure.yaml`, via AWS CloudFormation. Summary of the resources created:

| Resource (Logical ID) | Type | Name / Identifier |
|---|---|---|
| `OpsVPC` | `AWS::EC2::VPC` | `Ops-VPC-Lab` (`10.0.0.0/16`) |
| `OpsInternetGateway` | `AWS::EC2::InternetGateway` | `Ops-IGW-Lab` |
| `OpsPublicSubnet` | `AWS::EC2::Subnet` | `Ops-Public-Subnet` (`10.0.1.0/24`) |
| `OpsPublicRouteTable` | `AWS::EC2::RouteTable` | `Ops-Public-RT` |
| `OpsSecurityGroup` | `AWS::EC2::SecurityGroup` | `Ops-Web-SG` |
| `OpsSNSTopic` | `AWS::SNS::Topic` | `Alertas-Restart-JVM-Lab` |
| `EC2InstanceProfile` | `AWS::IAM::InstanceProfile` | `EC2-SSM-Operations-Profile-Lab` |
| `AppServerEC2` | `AWS::EC2::Instance` | Tag `Name = US-PRD-AWS-001` |
| `AppS3Bucket` | `AWS::S3::Bucket` | `jvm-status-ops-01a` |
| `HardRestartJVMDocument` | `AWS::SSM::Document` (Automation) | `HardRestart-JVM-App` |

### Networking (VPC, Subnet, Internet Gateway, Security Group)

The infrastructure provisions its own isolated network, which makes the Stack self-sufficient and portable across accounts and regions; this way, you can focus on understanding how building automations with AWS SSM works:

- A **VPC** (`OpsVPC`, `10.0.0.0/16`) with DNS support enabled;
- A **Public Subnet** (`OpsPublicSubnet`, `10.0.1.0/24`), with automatic public IP assignment;
- An **Internet Gateway** (`OpsInternetGateway`) attached to the VPC, and a **Route Table** (`OpsPublicRouteTable`) with a `0.0.0.0/0` route pointing to it;
- A **Security Group** (`OpsSecurityGroup`) opening port 80, HTTP, to any origin, with default outbound access allowed.

Port 80 is already open from the very first deploy, with no manual step needed afterward (see [Step-by-Step Guide](#step-by-step-guide)).

### EC2 Instance (`AppServerEC2`)

A single `t3.micro` running **Amazon Linux 2023**. All initial provisioning happens via `UserData`, run automatically on first boot:

- Installs **Amazon Corretto 17** (Amazon's JDK for Java) and **NGINX**;
- Creates the folder structure used by the whole application: `/suporteapp/app`, `/suporteapp/deploy`, and `/suporteapp/logs/<jvm>` for each of the 4 JVMs;
- Sets the folder owner to `ec2-user`, which avoids running the application as `root`;
- Enables and starts NGINX.

The instance is associated with the `OpsPublicSubnet` and `OpsSecurityGroup` described above, isolated from the account's default VPC infrastructure. Note that the template **does not define** a key pair (`KeyName`); access is done entirely via **SSM Session Manager**, without relying on SSH.

### IAM Instance Profile (`EC2InstanceProfile`)

For the instance to be able to talk to SSM, which is essential for everything, Session Manager, Run Command, and the Automation itself, it needs an Instance Profile attached to a Role with the right permissions, basically, the `AmazonSSMManagedInstanceCore` managed policy.

In regular accounts, the usual path would be to create a new Role just for this. In student or lab accounts, like the AWS Academy Learner Lab, creating new Roles tends to be blocked by account policy. For that reason, the template takes the name of an **existing** Role as a parameter, `ExistingLabRoleName`, defaulting to `LabRole`, and simply attaches that Role to the Instance Profile.

### S3 Bucket (`AppS3Bucket`)

Stores the `status.war` artifact, the application "package" distributed to the 4 JVMs. The goal is to have a simple deployment repository, from which the object can be downloaded directly on the instance using the AWS CLI.

### SNS Topic (`OpsSNSTopic`)

The notification channel the runbook uses to report when a recovery action is executed. The message is formatted as plain text with ASCII borders, since lab environments generally only support that format for SNS emails, no HTML. The subscription, the email address that receives the alerts, **is not created automatically** by the template; it's left as a manual step (see [Step-by-Step Guide](#step-by-step-guide)), since in a lab it's usually simpler to set that up directly through the Console.

### SSM Automation Document (`HardRestartJVMDocument`)

The heart of the automation. An `Automation`-type runbook (schema `0.3`) with two steps:

**1. `ExecutarRestart`** — via `aws:runCommand`, remotely runs, on the instance identified by the `Name` tag, a fairly simple shell script:

```bash
JVM="{{ JvmName }}"
PID=$(ps -ef | grep "/suporteapp/app/tomcat_$JVM" | grep -v grep | awk '{print $2}')
if [ -n "$PID" ]; then
    kill -9 $PID
    sleep 5
fi
sudo su - ec2-user -c "sh /suporteapp/app/tomcat_$JVM/bin/startup.sh"
```

In other words: it finds the process for the given JVM, forces it to stop (`kill -9`), waits 5 seconds, and brings the application back up through Apache Tomcat's standard script.

> 💡 In production, the ideal approach is always to try a "graceful" shutdown first using `shutdown.sh`, which sends SIGTERM and gives the JVM a chance to close connections and release resources before dying, leaving `kill -9`/SIGKILL as a last resort. The runbook's name (`HardRestart`) is intentional: the goal here is to specifically simulate a stuck JVM that doesn't respond even to a graceful shutdown, by running a simple script.
>
> A natural next step would be for the automation to try `shutdown.sh` first, with a timeout, and only fall back to `kill -9` if the process is still up afterward.

**2. `NotificarOps`** — via `aws:executeAwsApi`, publishes a message to the SNS topic with the action's details, including the server name, the JVM, what was done, and the suggested next steps for whoever receives the alert.

> 💡 For a single server, connecting to the instance via SSH would solve the problem quickly. Automation pays off precisely when this scenario repeats or multiplies: it guarantees the same procedure runs the same way every time, doesn't depend on who's on call, or on "how each person would do it their own way," and on top of that, the run gets logged in the SSM execution history, including who ran it, when, and with which parameters, and it doesn't require handing out interactive access, such as SSH or Session Manager, to everyone who might eventually need to restart something.
>
> The same automation could also be triggered automatically by an Amazon CloudWatch alarm, with no human intervention at all.

### NGINX + Apache Tomcat (Application Layer)

Unlike the resources above, NGINX and the 4 Tomcat instances **are not managed by CloudFormation**; they're installed and configured after the instance is already up, through `jvms_config.sh` (see [Step-by-Step Guide](#step-by-step-guide)), which makes it easier to follow each step being performed. Each JVM runs Apache Tomcat 9.0.120 in its own directory (`tomcat_usprd01a`, `tomcat_usprd02b`, `tomcat_usprd03c`, `tomcat_usprd04d`), with its own port and its own `setenv.sh` setting variables like `JVM_NAME` and the log path (`CATALINA_OUT`). NGINX distributes requests across the 4 local ports in round-robin.

### Status Application (`index.jsp` + `web.xml` → `status.war`)

The sample application is simple and to the point: a single JSP page that uses Java's `InetAddress` API to capture the machine's hostname and IP, `System.getProperty("os.name")` for the operating system, and the `JVM_NAME` environment variable, set in each JVM's `setenv.sh`, to identify which instance responded. `web.xml` only declares the application name; there's no Servlet mapping at all, so Tomcat itself serves `index.jsp` as the default page.

Packaged as `ROOT.war`, it's reachable at the root (`/`) of each JVM. As soon as a request comes in, when you run the application, notice that the `Hostname` and `IP Interno` (internal IP) fields are the same across all 4 JVMs, since it's the same EC2 instance after all; what actually changes is the `JVM Name`.

## Prerequisites

- **AWS Account** — this can be a personal account (Free Tier) or a lab environment like **AWS Academy Learner Lab / VocLabs by Vocareum Labs**. If it's a lab, keep a few things in mind:
  - Sessions tend to have a limited duration and credentials expire; you'll usually need to copy the temporary credentials, Access Key, Secret Key, and **Session Token**, from the lab dashboard into your `~/.aws/credentials` whenever the session renews;
  - You can't create new IAM Roles/Policies, which is why the template uses an existing Role, such as `LabRole`, by default;
  - The region tends to be fixed, usually `us-east-1`, and the instance type tends to be limited to small families, such as `t2.micro` and `t3.micro`;
  - Resources are automatically deleted at the end of the lab; nothing here is permanent between sessions unless you redeploy it. In some labs that run on credits, resources stay up until the credits run out.
- **AWS CLI** — installed and configured, use `aws configure`, or the lab's temporary credentials;
- **Windows PowerShell** — the local automation scripts, such as `cfn_manage_stack.ps1` and `s3_manage_object.ps1`, were written for PowerShell. On Linux/macOS, the same `aws` commands work fine in Bash, just swap PowerShell's line continuation `` ` `` for `\` in Bash;
- **JDK** installed locally — needed to package `status.war` with the `jar` command;
- A **browser**, to check the application;
- **Session Manager plugin for the AWS CLI** — optional, only needed if you want to use `aws ssm start-session` from the terminal. Through the AWS Console, Session Manager works right from the browser, no extra install needed, recommended if you're just getting started.

## Step-by-Step Guide

> ⚠️ It's recommended to change resource names to unique identifiers within your own environment, for example: `myapp-prod-bucket-2026`, since some AWS services don't accept duplicate names.

### 1. Packaging the status application (`status.war`)

The project includes the application's source code (`index.jsp` and `web.xml`), but not the compiled `.war` itself; this package needs to be built first, since the following steps depend on it. Organize the files following the standard structure of a Java Web application:

```
status-app/
├── index.jsp
└── WEB-INF/
    └── web.xml
```

Then build the `.war` with the JDK itself:

```powershell
mkdir status-app\WEB-INF
copy index.jsp status-app\
copy web.xml status-app\WEB-INF\
cd status-app
jar -cvf ..\status.war *
cd ..
```

*(On Linux/macOS: `mkdir -p status-app/WEB-INF`, `cp` instead of `copy`, and the same `jar` command.)*

### 2. Deploying the infrastructure (CloudFormation)

With `jvm_infrastructure.yaml` in place, create the Stack:

```powershell
aws cloudformation create-stack `
--stack-name JVMStatusLab `
--template-body file://infra/jvm_infrastructure.yaml `
--capabilities CAPABILITY_NAMED_IAM
```

This command already provisions the entire network stack, VPC, Subnet, Internet Gateway, and Security Group, along with the compute, storage, and automation pieces; there's no networking left to set up by hand afterward.

> 💡 `--capabilities CAPABILITY_NAMED_IAM` is required because the Stack creates an IAM resource with an explicitly defined name, the Instance Profile. Without this flag, creation fails asking for that confirmation; it's an AWS safeguard against unintentionally creating identity and access resources.

If your lab's default Role name is different from `LabRole`, in some environments it's `voclabs`, provide the parameter:

```powershell
aws cloudformation create-stack `
--stack-name JVMStatusLab `
--template-body file://infra/jvm_infrastructure.yaml `
--parameters ParameterKey=ExistingLabRoleName,ParameterValue=YOUR_ROLE_NAME `
--capabilities CAPABILITY_NAMED_IAM
```

Track the status until `CREATE_COMPLETE`, either through the AWS Management Console or by running:

```powershell
aws cloudformation describe-stacks --stack-name JVMStatusLab --query "Stacks[0].StackStatus"
```

To reapply any change to the template later, use `update-stack`:

```powershell
aws cloudformation update-stack `
--stack-name JVMStatusLab `
--template-body file://infra/jvm_infrastructure.yaml `
--capabilities CAPABILITY_NAMED_IAM
```

> ⚠️ S3 Bucket names are **globally** unique across every AWS account in the world, not just yours. If the name is already taken by another account, the deploy will fail. Adjust `BucketName` in the template and try again.

### 3. Uploading `status.war` to S3

With the Bucket already created by the Stack, upload the package built in Step 1:

```powershell
aws s3api put-object `
--bucket jvm-status-ops-01a `
--key status.war `
--body .\status.war
```

### 4. Confirming the Email Subscription in SNS

Automatically creating the subscription was left out of the template because, for the specific purpose of this lab, testing the automation, it's recommended to set up the subscription through the AWS Management Console. If you'd rather do it via the AWS CLI, just follow these commands:

```powershell
aws sns list-topics `
--query "Topics[?contains(TopicArn, 'Alertas-Restart-JVM-Lab')].TopicArn" `
--output text
```

Then create the subscription with your email:

```powershell
aws sns subscribe `
--topic-arn ARN_FROM_ABOVE `
--protocol email `
--notification-endpoint your-email@example.com
```

Confirm the subscription through the link that arrives in your inbox; without that confirmation, the topic won't deliver anything.

### 5. Connecting to the Instance via SSM Session Manager

With no SSH key, the connection is made straight from the Console: **EC2 → Instances → select the instance tagged `US-PRD-AWS-001` → Connect → Session Manager → Connect**. This opens a terminal right in your browser.

*(Alternative via the AWS CLI, requires the AWS Session Manager plugin installed locally: `aws ssm start-session --target INSTANCE_ID`.)*

### 6. Installing and Configuring Tomcat and the 4 JVMs

With the session open, follow `jvms_config.sh`; it was designed to be run in parts, manually, since it has a few manual editing points, making it easier to follow for anyone just getting started. Summary of the blocks:

1. Downloads and extracts Apache Tomcat 9.0.120 into `/tmp`;
2. Copies that same install 4 times, one for each JVM (`tomcat_usprd01a` through `tomcat_usprd04d`);
3. **Manual edit:** adjusts the ports in each `server.xml`; the first JVM keeps Tomcat's default ports, the rest need to change. This can be done via `vi`/`nano`, or more directly with `sed`, assuming the default Tomcat `server.xml`, with no prior changes:

   | JVM | Server Port | Connector Port |
   |---|---|---|
   | `usprd01a` | 8005 *(default)* | 8080 *(default)* |
   | `usprd02b` | 8006 | 8081 |
   | `usprd03c` | 8007 | 8082 |
   | `usprd04d` | 8008 | 8083 |

   ```bash
   sudo sed -i 's/port="8005"/port="8006"/; s/port="8080"/port="8081"/' /suporteapp/app/tomcat_usprd02b/conf/server.xml
   sudo sed -i 's/port="8005"/port="8007"/; s/port="8080"/port="8082"/' /suporteapp/app/tomcat_usprd03c/conf/server.xml
   sudo sed -i 's/port="8005"/port="8008"/; s/port="8080"/port="8083"/' /suporteapp/app/tomcat_usprd04d/conf/server.xml
   ```

4. Sets folder ownership to `ec2-user`;
5. Downloads `status.war` from S3 and copies it to the central deploy folder (`/suporteapp/deploy/ROOT.war`);
6. Removes the default welcome `ROOT` from each JVM (`webapps/ROOT*`) before rolling out the new version; Tomcat ships with that folder already extracted by default, and without this cleanup it can keep serving the old page instead of the application;
7. Copies `ROOT.war` to all 4 JVMs, so each one serves the application at the root `/`, with no extra context needed in the URL;
8. Creates each JVM's `setenv.sh`, setting `JVM_NAME`, used by the status page, and the log path (`CATALINA_OUT`);
9. Starts up the 4 JVMs with `startup.sh`.

### 7. Configuring NGINX as a Load Balancer

Still in `jvms_config.sh`, the last manual block is NGINX. Edit `/etc/nginx/nginx.conf` and, **inside the `http { }` block but outside the `server { }` block**, add:

```nginx
upstream cluster_jvms {
    server 127.0.0.1:8080; # usprd01a
    server 127.0.0.1:8081; # usprd02b
    server 127.0.0.1:8082; # usprd03c
    server 127.0.0.1:8083; # usprd04d
}
```

Then, inside the existing `server { }` block, adjust `location / { }` to point to that group:

```nginx
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://cluster_jvms;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Restart NGINX to apply it:

```bash
sudo systemctl restart nginx
```

### 8. Validating the Environment

Confirm that all 4 processes are up:

```bash
ps -ef | grep tomcat
```

Port 80 is already open thanks to the Security Group created with the Stack; grab the public IP through the AWS Management Console, or with the command below, and check it in your browser:

```powershell
aws ec2 describe-instances `
--filters "Name=tag:Name,Values=US-PRD-AWS-001" `
--query "Reservations[].Instances[].PublicIpAddress" `
--output text
```

Refresh the page a few times and the `JVM Name` shown should cycle through the 4 instances; that's a sign NGINX's round-robin load balancing is working.

<p align="center">
  <img src="./images/app.png" alt="JVM Status" width="99%">
</p>

### 9. Testing the Hard Restart Automation

Through the Console: **Systems Manager → Automation → Execute automation → search for `HardRestart-JVM-App`** → provide `HostName` (`US-PRD-AWS-001`) and `JvmName` (e.g., `usprd01a`) → Execute.

Or via the AWS CLI:

```powershell
aws ssm start-automation-execution `
--document-name "HardRestart-JVM-App" `
--parameters "HostName=US-PRD-AWS-001,JvmName=usprd01a"
```

Follow the steps (`ExecutarRestart` and `NotificarOps`) as they run, and check whether the email set up in step 4 arrived, with the subject `[Ops] Automated Recovery Action Executed`.

<p align="center">
  <img src="./images/email.png" alt="E-mail" width="90%">
</p>

## Cleaning Up Resources

Especially important in lab and Free Tier environments; nothing here costs anything if it's deleted properly, but it's a good habit regardless.

> ⚠️ `cfn_manage_stack.ps1` doesn't include a delete command; the commands below were added here to close that loop, since labs tend to have limited quotas and/or session time.

**1. Empty the S3 Bucket first.** CloudFormation can only delete an empty bucket; if `status.war` is still in there, the Stack deletion fails on that resource:

```powershell
aws s3api delete-object `
--bucket jvm-status-ops-01a `
--key status.war
```

**2. Delete the Stack:**

```powershell
aws cloudformation delete-stack `
--stack-name JVMStatusLab
```

This also removes the VPC, the Subnet, the Internet Gateway, and the Security Group created with it; there's no orphaned networking resource left to delete separately.

**3. Track it through the AWS Management Console or with the command below until the deletion finishes:**

```powershell
aws cloudformation describe-stacks --stack-name JVMStatusLab
```

*(Once this command returns an error saying the Stack no longer exists, the deletion is complete.)*

## Troubleshooting

- **The instance doesn't show up in Session Manager / Fleet Manager** — wait a few minutes after `CREATE_COMPLETE`; the SSM agent takes a bit to register itself, and confirm the Instance Profile was attached correctly.
- **Error asking for `CAPABILITY_NAMED_IAM`** — you forgot to include that flag in `create-stack`/`update-stack` (see [step 2](#step-by-step-guide)).
- **Role/Instance Profile error when creating the Stack** — the default name (`LabRole`) can vary between labs, sometimes it's `voclabs`; adjust the `ExistingLabRoleName` parameter.
- **Bucket already exists error** — S3 bucket names are globally unique; change `BucketName` in the template.
- **Invalid `ImageId` / AMI not found** — the template's AMI ID is specific to a region, `us-east-1`, typically, in AWS Academy environments. In a different region, look up the correct Amazon Linux 2023 ID there.
- **502 Bad Gateway on NGINX** — usually means one or more JVMs haven't come up yet, or failed to start. Check with `ps -ef | grep tomcat` and the logs at `/suporteapp/logs/<jvm>/SystemOut.log`.
- **Page won't load in the browser, but the processes are up** — likely the Security Group; confirm that `OpsSecurityGroup` is actually attached to the instance and has port 80 open (see [Infrastructure Components](#infrastructure-components)). Also worth checking whether the browser is forcing HTTPS; if it is, just switch to HTTP.
- **Expired credentials** — lab sessions have a limited duration; copy the refreshed temporary credentials into your `~/.aws/credentials` whenever needed.
- **The automation can't find its target (`Targets`)** — confirm the instance's `Name` tag exactly matches the `HostName` given at execution time.

## Limitations and Possible Improvements

> 💡 The goal here wasn't to deliver something production-ready, but to build hands-on familiarity with a few fundamental concepts, Infrastructure as Code, remote execution without interactive access, asynchronous notification, in a deliberately simple way, so that someone just getting started can understand how these automations work, all within the limits of a free/lab environment.
