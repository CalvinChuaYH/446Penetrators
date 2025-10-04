import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle
} from "@/components/ui/card";

import Navbar from "./components/navbar";

  const blogPosts = [
    {
      title: "Getting Started with React",
      content: "React makes it painless to create interactive UIs. In this post, we'll explore how to set up your first project...",
      username: "username1"
    },
    {
      title: "Understanding Tailwind CSS",
      content: "Tailwind CSS is a utility-first CSS framework. Let's see how it helps you build fast UIs...",
      username: "username2"
    }
  ]


function Home() {
    return (
        <div className="flex flex-col justify-center items-center">
            <Navbar />
            <div className="flex flex-col gap-12 mt-12">
                {blogPosts.map(post => (
                    <Card key={post.username}>
                        <CardHeader>
                            <CardTitle>{post.title}</CardTitle>
                            <CardDescription>{post.username}</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <p>{post.content}</p>
                        </CardContent>
                    </Card> 
                ))}
            </div>
        </div>
    )
}

export default Home;