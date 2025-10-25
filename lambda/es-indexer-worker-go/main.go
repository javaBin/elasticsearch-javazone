package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

var (
	moresleepURL  = os.Getenv("MORESLEEP_API_URL")
	moresleepUser = os.Getenv("MORESLEEP_USERNAME")
	moresleepPass = os.Getenv("MORESLEEP_PASSWORD")
	esURL         = os.Getenv("ELASTICSEARCH_URL")
	esUser        = os.Getenv("ELASTICSEARCH_USERNAME")
	esPass        = os.Getenv("ELASTICSEARCH_PASSWORD")
	esIndex       = os.Getenv("ELASTICSEARCH_INDEX")
	httpClient    = &http.Client{}
)

type WebhookEvent struct {
	EventID      string `json:"eventId"`
	EventType    string `json:"eventType"`
	EntityID     string `json:"entityId"`
	ConferenceID string `json:"conferenceId"`
}

func handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	for _, record := range sqsEvent.Records {
		var event WebhookEvent
		if err := json.Unmarshal([]byte(record.Body), &event); err != nil {
			fmt.Printf("Error parsing event: %v\n", err)
			continue
		}

		fmt.Printf("Processing %s for talk %s\n", event.EventType, event.EntityID)

		switch event.EventType {
		case "talk.created", "talk.updated", "talk.published":
			if err := indexTalk(ctx, event.EntityID); err != nil {
				fmt.Printf("Error indexing talk %s: %v\n", event.EntityID, err)
				return err // Return error to retry
			}
		case "talk.unpublished":
			if err := updateTalkStatus(ctx, event.EntityID, "DRAFT"); err != nil {
				fmt.Printf("Error updating talk %s: %v\n", event.EntityID, err)
				return err
			}
		}
	}

	return nil
}

func indexTalk(ctx context.Context, talkID string) error {
	// Fetch talk from moresleep
	talkData, err := fetchTalkFromMoresleep(talkID)
	if err != nil {
		return fmt.Errorf("fetch talk: %w", err)
	}

	// Transform to ES document
	esDoc := transformTalkToES(talkData)

	// Index to Elasticsearch
	return indexToElasticsearch(talkID, esDoc)
}

func fetchTalkFromMoresleep(talkID string) (map[string]interface{}, error) {
	url := fmt.Sprintf("%s/data/session/%s", moresleepURL, talkID)
	req, _ := http.NewRequest("GET", url, nil)

	if moresleepUser != "" && moresleepPass != "" {
		auth := base64.StdEncoding.EncodeToString([]byte(moresleepUser + ":" + moresleepPass))
		req.Header.Set("Authorization", "Basic "+auth)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("moresleep returned %d", resp.StatusCode)
	}

	var talk map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&talk); err != nil {
		return nil, err
	}

	return talk, nil
}

func transformTalkToES(talk map[string]interface{}) map[string]interface{} {
	// Simple transformation - extract key fields
	// TODO: Add logic to denormalize pkomfeedbacks (comments/ratings)
	return map[string]interface{}{
		"talkId":       talk["id"],
		"conferenceId": talk["conferenceid"],
		"status":       talk["status"],
		"data":         talk["data"],
		"speakers":     talk["speakers"],
		"lastUpdated":  talk["lastUpdated"],
	}
}

func indexToElasticsearch(talkID string, doc map[string]interface{}) error {
	docJSON, _ := json.Marshal(doc)

	url := fmt.Sprintf("%s/%s/_doc/%s", esURL, esIndex, talkID)
	req, _ := http.NewRequest("PUT", url, bytes.NewBuffer(docJSON))
	req.Header.Set("Content-Type", "application/json")

	if esUser != "" && esPass != "" {
		auth := base64.StdEncoding.EncodeToString([]byte(esUser + ":" + esPass))
		req.Header.Set("Authorization", "Basic "+auth)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ES returned %d: %s", resp.StatusCode, string(body))
	}

	fmt.Printf("Indexed talk %s to Elasticsearch\n", talkID)
	return nil
}

func updateTalkStatus(ctx context.Context, talkID, status string) error {
	url := fmt.Sprintf("%s/%s/_update/%s", esURL, esIndex, talkID)
	update := map[string]interface{}{
		"doc": map[string]interface{}{
			"status": status,
		},
	}

	updateJSON, _ := json.Marshal(update)
	req, _ := http.NewRequest("POST", url, bytes.NewBuffer(updateJSON))
	req.Header.Set("Content-Type", "application/json")

	if esUser != "" && esPass != "" {
		auth := base64.StdEncoding.EncodeToString([]byte(esUser + ":" + esPass))
		req.Header.Set("Authorization", "Basic "+auth)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	fmt.Printf("Updated talk %s status to %s\n", talkID, status)
	return nil
}

func main() {
	lambda.Start(handler)
}
