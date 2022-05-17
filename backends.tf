terraform {
  cloud {
    organization = "terransiblemp32"

    workspaces {
      name = "terransible"
    }
  }
}