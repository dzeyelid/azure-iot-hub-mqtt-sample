variable "identifier" {
  type = string
}

variable "location" {
  type = string
}

variable "iothub" {
  type = object({
    sku_name = string
  })
}
