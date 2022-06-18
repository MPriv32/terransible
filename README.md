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

Now it's time for the heart of the application, the functions that make it all work. The first function has the task of checking the repository's merge settings- are merge commits allowed? is squash merging allowed? rebase and merging? That's what this function will find out for us adn return either a ```True``` or ```False```:

```
def repo_merge_strategies(repo):
    #Check if merge commits are allowed
    if repo.allow_merge_commit == True:
        print("Merge commits are allowed!")
    else:
        print("Merge commits aren't allowed.")

    #Check if squash merging is allowed
    if repo.allow_squash_merge == True:
        print("Squash merging is allowed!")
    else:
        print("Squash merging isn't allowed.")

    #Check if rebase and merging is allowed
    if repo.allow_rebase_merge == True:
        print("Rebase and merge is allowed!")
    else:
        print("Rebase and merge isn't allowed.")
```

The second function has the task of checking if auto head branch deletion protuction is enabled. This function is separate from the other function, mainly because the first function only requires the name of a repository to run. The second function, needs the repository name and the name of the head branch, which is "main" in this case.

```
def auto_delete_enabled(branch):
    if branch.protected == True:
        print("Auto delete head branch is disabled!")
    else:
        print("Auto delete head branch is enabled.") 
```

The final piece to the application is the **for loop** that runs each function using each repository name from out list of repositories. In this function, we assign the value **repo** to our repo name, **branch** which is a combination of the repo name and the head branch "main". Then it runs both functions with the appropriate values as inputs.

```
for repo in repo_list:
    repo = g.get_repo(repo)
    branch = repo.get_branch("main")
    repo_merge_strategies(repo)
    auto_delete_enabled(branch) 
```

Running the application is simple: Create a DynamoDB table with the primary key of ```repo``` and the items can be repository names. Configure your environment variables and run the application- very minimal changes are required if you'd rather pass in the list of repositories using a different method.

### Passing in a list of repos
