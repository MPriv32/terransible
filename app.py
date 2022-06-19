from github import Github
import os
import botocore
import boto3
import json

#Specify .env folder to store credentials
if os.path.isfile('.env'):
    from dotenv import load_dotenv
    load_dotenv()

#Authorization for DynamoDB
AWS_ACCESS_KEY = os.getenv('AWS_ACCESS_KEY')
AWS_SECRET_KEY = os.getenv('AWS_SECRET_KEY')
REGION = os.getenv('REGION')
TABLE_NAME = os.getenv('TABLE_NAME')

#DynamoDB table that contains the repo list
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(TABLE_NAME)

# Scans repo names from DB and return a list of repos
try:    
    response = table.scan()
    data = response['Items']
except botocore.exceptions.ClientError as error:
    print(error)

finally: 
    repo_list = [x.get("repo") for x in data]



#Authorization to access repo data
access_token = os.getenv("GITHUB_ACCESS_TOKEN")
g = Github(access_token)

#Creates an empty list, so when our functions run, we can add the values to this list
list = []

#Specifies whether merge commits, squash merging and rebase & merge are allowed
def repo_merge_strategies(repo):
    #Check if merge commits are allowed
    list.append({'Merge Commits': repo.allow_merge_commit})

    #Check if squash merging is allowed
    list.append({'Squash Merging': repo.allow_squash_merge})

    #Check if rebase and merging is allowed
    list.append({'Rebase and Merging': repo.allow_rebase_merge})

#Specifies if the head branch is set to auto delete after pull requests are merged
def auto_delete_enabled(branch):
    list.append({'Head Delete Protection': branch.protected})

#Loop through list of repos
for repo in repo_list:
    repo = g.get_repo(repo)
    branch = repo.get_branch("main")
    repo_merge_strategies(repo)
    auto_delete_enabled(branch)

#Export results as json data to repos.json
jsonData = json.dumps(list)
with open('repos.json', 'w', newline='') as outfile:
    outfile.write(jsonData)
print(jsonData)