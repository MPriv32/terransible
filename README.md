# Tackle Take Home Project

## Outline
- **Application overview and how to use it**
- **Passing in a list of repos**
- **Passing in application configuration**
- **Deploying to Lambda**
- **Deploying to EKS**
- **Considerations for passing credentials and storing artifacts**

## Application overview and how to use it

This application is used for scanning a list of GitHub repositories to check for certain parameters, such as:
- If merge commits are allowed
- If squash merging is allowed
- If rebase and merging is allowed
- If auto-delete head branch protection is enabled/disabled

### Code Walkthrough

Start by creating a python file ``` app.py ```

In ``` app.py ``` , we'll import the required modules for this application

```
from github import Github
import os
import boto3 
```

We use the **github** module in order to make api calls to the GitHub API. This is how we scan a repository for certain attributes, such as the merge and auto-delete configurations.
The **os** module is used to pass in environment variables for our application- which we use for passing in credentials and application configuration, locally.
**Boto3** is the offical AWS SDK to create, configure and manage AWS services. We use this to run a table scan on our DynamoDB table.

Now, it's time to pass in those environment variables. For simplicity, you can create a ```.env``` file in the same directory as ```app.py``` and implement this code to the application.

```
if os.path.isfile('.env'):
    from dotenv import load_dotenv
    load_dotenv()
```

Then we create some variables and pass them in using ```os.getenv``` followed by the name of the variable, like-so

```
AWS_ACCESS_KEY = os.getenv('AWS_ACCESS_KEY')
AWS_SECRET_KEY = os.getenv('AWS_SECRET_KEY')
REGION = os.getenv('REGION')
TABLE_NAME = os.getenv('TABLE_NAME')
```

The ```.env``` file should look like this:

```
AWS_ACCESS_KEY = "<insert access key>"
AWS_SECRET_KEY = "<insert secret key>"
REGION = "<insert region>"
TABLE_NAME = "<insert table name>"
```

Back to our application in ```app.py``` we need to assign a value to ```boto3.resource('dynamodb')``` and assign another value to the DynamoDB table we'll be using. After this, we'll run a table scan to return every item in the table, which in our case, is a list of repository names. This will return a list of key-value pairs. In python, we can use the ```get()``` function and specifiy the key- it will return the value and then we'll create a new list of just the values (repository names). Here's what that code looks like

```
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

response = table.scan()
data = response['Items']
repo_list = [x.get("repo") for x in data]
```

For the final step of authorization, we need to authorize with ```github``` using a personal access token with the appropriate permissions.

```
access_token = os.getenv("GITHUB_ACCESS_TOKEN")
g = Github(access_token)
```

Now it's time for the heart of the application, the functions that make it all work. The first function has the task of checking the repository's merge settings- are merge commits allowed? is squash merging allowed? rebase and merging? That's what this function will find out for us and return either a ```True``` or ```False``` as a key-value pair and add it to a list:

```
def repo_merge_strategies(repo):
    #Check if merge commits are allowed
    list.append({'Merge Commits': repo.allow_merge_commit})

    #Check if squash merging is allowed
    list.append({'Squash Merging': repo.allow_squash_merge})

    #Check if rebase and merging is allowed
    list.append({'Rebase and Merging': repo.allow_rebase_merge})
```

The second function has the task of checking if auto head branch deletion protuction is enabled. This function is separate from the other function, mainly because the first function only requires the name of a repository to run. The second function, needs the repository name and the name of the head branch, which is "main" in this case.

```
def auto_delete_enabled(branch):
    if branch.protected == True:
        print("Auto delete head branch is disabled!")
    else:
        print("Auto delete head branch is enabled.") 
```

Now we implement the **for loop** that runs each function with every repo from the list of repositories. In this function, we assign the value **repo** to our repo name, **branch** which is a combination of the repo name and the head branch "main". Then it runs both functions with the appropriate values as inputs.

```
for repo in repo_list:
    repo = g.get_repo(repo)
    branch = repo.get_branch("main")
    repo_merge_strategies(repo)
    auto_delete_enabled(branch) 
```

Lastly, we convert our list of values into json and export it to a json file:

```
jsonData = json.dumps(list)
with open('repos.json', 'w', newline='') as outfile:
    outfile.write(jsonData)
print(jsonData)
```

Running the application is simple: Create a DynamoDB table with the primary key of ```repo``` and the items can be repository names. Configure your environment variables and run the application- very minimal changes are required if you'd rather pass in the list of repositories using a different method.

### Passing in a list of repos

The chosen way to pass in the list of repos was via a database, as it's a a common way to pass in data to an application. I considered setting up the application to take in a list of repos via a json file, but this wouldn't be logical if we decided to deploy the application to multiple instances. It's far easier to manage one database that every instance pulls from, as opposed to having to manage the data on each individual instance.

### Passing in application configuration

The configuration for this application is passed in via environment variables, as this is a flexible way to pass in application configuration. Environment variables can be passed in locally from a .env file, they can be passed in from the CLI- such as when deploying to Lambda or EKS. They can be passed in when deploying the infrastructure through IaC services like Terraform, configuration files for kubernetes etc.

### Deploying to Lambda

For deploying the application to Lambda, there's only one change that needs to be made to the application code itself- the **for loop** needs to be wrapped in a handler function for lambda. Here's an example of that

```
def handler (event, context):  
    #Loop through list of repos
    for repo in repo_list:
        repo = g.get_repo(repo)
        branch = repo.get_branch("main")
        repo_merge_strategies(repo)
        auto_delete_enabled(branch)

handler(None, None)
```

Most of the changes or additions need to happen from outside the application. A great way to get started with deploying the application to Lambda is to start in the CLI.

First, we'll need a repository to store the image and **ECR** is a simple way to do so. Using the AWS CLI run the ensuing command (all CLI examples come directly from the AWS docs):

```
aws ecr create-repository \
    --repository-name TackleTakeHome \
    --image-scanning-configuration scanOnPush=true \
    --region us-west-2
```
After creating the repository, we need to build and push a docker image to it, so creating a docker image would be a good start. Here's the ```Dockerfile``` required to get the application up and running on Lambda:

```
FROM amazon/aws-lambda-python:3.8

# Copy function code
COPY app.py ${LAMBDA_TASK_ROOT}

#Copy and install requirements
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN pip install -r requirements.txt

ARG GITHUB_ACCESS_TOKEN
ARG TABLE_NAME

ENV GITHUB_ACCESS_TOKEN $GITHUB_ACCESS_TOKEN
ENV TABLE_NAME $TABLE_NAME

# Set the CMD to the handler 
CMD [ "app.handler" ]
```

After doing this, run the following commands to build, tag and push your image to ECR:

Start by authenticating Docker with your registry

```aws ecr get-login-password --region region | docker login --username AWS --password-stdin <aws_account_id>.dkr.ecr.<region>.amazonaws.com``` 

Building the image

```docker build -t TackleTakeHome .```

Tagging the image

```docker tag TackleTakeHome:latest <aws_account_id>.dkr.ecr.<region>.amazonaws.com/TackleTakeHome:latest```

Pushing the image

```docker push <aws_account_id>.dkr.ecr.<region>.amazonaws.com/TackleTakeHome:latest```

Now that the application is on ECR, we just need to create a Lambda function from the image.
**Note:** The Lambda functions needs certain permissions to run this application, it needs an IAM role with ```AmazonDynamoDBReadOnlyAccess``` and ```AWSLambdaBasicExecutionRole``` permissions. This allows the app to send logs to cloudwatch and to scan the DynamoDB table.

Once the Lambda function is created, we just need to pass in a couple of the environment variables from the CLI. You can do so from running 

```
aws lambda update-function-configuration --function-name my-function \
    --environment "Variables={BUCKET=my-bucket,KEY=file.txt}"
```
You can replace these environment variables with the ones we used in our ```.env``` file.

## Deploying to EKS

If we choose to deploy to EKS, no changes need to be made to the original code that we first created. Only some minor changes need to be made to the ```Dockerfile```.
We no longer need to copy our application to ```${LAMBDA_TASK_ROOT}``` we can copy it to whatever directory we want and changed the **CMD** from ```CMD [ "app.handler" ]``` to ```CMD ["python", "app.py"]```

After those changes are made, we can repeat the previous steps to build, tag and push it to ECR. 

Being that it's an API, we have two options of running the appliation on EKs: we can run it once as a **batch job**, or run it periodically as a **CRON job**.
This should be taken into consideration when creating the Kubernetes manifests for the cluster.

## Considerations for passing credentials and storing artifacts

As per the AWS docs, the best way to pass crfedentials to your application is by using temporary credentials with STS. Another option, however, is to use AWS Secrets Manager. AWS Secrets Manager will automatically rotate your keys and allows you to easily manage your secrets from one central location, that can easily be replicated across regions. 

Two common ways to store build artifacts include S3 or AWS CodeArtifact. AWS CodeArtifact is just an AWS managed service that uses S3 and DynamoDB as it's backend. Choosing between the two depends on how much configuration, operational overhead and financial overhead you're willing to allocate.
